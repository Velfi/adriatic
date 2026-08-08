#+feature using-stmt
package main

import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import chase_camera "../packages/chase_camera"
import engine_sound "../packages/engine_sound"
import flight "../packages/flight"
import libellula_game "../packages/libellula"
import ocean_audio "../packages/ocean_audio"
import particle_systems "../packages/particles"
import postale_game "../packages/postale"
import roads "../packages/roads"
import rondine_game "../packages/rondine"
import scene_stack "../packages/scene_stack"
import spray_audio "../packages/spray_audio"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import wind_audio "../packages/wind_audio"
import "core:fmt"
import "core:math"
import "core:time"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import dio "zelda_engine:dio"
import game_input "zelda_engine:game_input"
import physics "zelda_engine:physics"
import third_person "zelda_engine:third_person"

run_frame_simulate_gameplay :: proc(using run: ^Run_State, using frame_state: ^Run_Frame_State) -> bool {
    crash_severity = f32(0)
    crash_water_mix = f32(0)
    crash_slide_speed = f32(0)
    crash_surface = engine_sound.Crash_Surface.Dirt
    crash_profile = engine_sound.Crash_Profile.Car
    crash_wetness = surface_weather_sample(editor, active_surface_weather_position(editor))
    crash_obliqueness = f32(0)
    crash_pan = f32(0)
    footstep_triggered = false
    footstep_intensity = f32(0)
    footstep_surface = engine_sound.Footstep_Surface.Grass
    footstep_landing = false
    footstep_slide = f32(0)
    crash_recovery_update(editor, simulation_delta)
    if editor.in_map &&
       lab_scene_allows_gameplay(editor) &&
       !pause_menu_is_open(editor) &&
       simulation_delta > 0 &&
       !capture_car_mode &&
       !cinematic_is_playing(editor) &&
       !crash_recovery_active(editor) {
        // A menu can close while input is processed. Keep the frame that
        // began paused frozen so its closing click or held controls cannot
        // leak into gameplay.
        delta_seconds := simulation_delta
        if editor.vehicle_paint_scene {
            vehicle_paint_process_input(editor, width, height, min(delta_seconds, .05))
        } else if editor.vehicle_showcase_scene {
            // Capture setup installs a deterministic target-specific pose.
            // Preserve it instead of replacing it with the interactive
            // orbit camera on the first frame.
            if !capture_mode do vehicle_showcase_camera_step(editor, min(delta_seconds, .05))
        } else {
            mouse_delta := canvas2d.GetMouseDelta()
            look_scale := editor.gameplay_options.look_sensitivity / .012
            look_x := editor.gameplay_options.invert_look_x ? -mouse_delta.x : mouse_delta.x
            look_y := editor.gameplay_options.invert_look_y ? -mouse_delta.y : mouse_delta.y
            flying := driving_aircraft(editor)
            in_car := driving_car(editor)
            if flying {
                if canvas2d.IsKeyPressed(.B) || gamepad_pressed(.Dpad_Down) {
                    editor.bomber_mode = !editor.bomber_mode
                }
                if editor.bomber_mode && (canvas2d.IsKeyPressed(.X) || gamepad_pressed(.Dpad_Left)) {
                    bomber_drop_release(editor)
                }
                if editor.bomber_mode && (canvas2d.IsKeyPressed(.V) || gamepad_pressed(.Dpad_Right)) {
                    bomber_payload_cycle(editor)
                }
                if !editor.bomber_mode {
                    flight_stick_x := gamepad_axis(.Right_X) * 700 * delta_seconds
                    if editor.gameplay_options.invert_look_x do flight_stick_x = -flight_stick_x
                    flight_stick_y := gamepad_axis(.Right_Y) * 700 * delta_seconds
                    if editor.gameplay_options.invert_look_y do flight_stick_y = -flight_stick_y
                    flight_look_x := look_x * look_scale + flight_stick_x
                    flight_look_y := look_y * look_scale + flight_stick_y
                    chase_camera.look(&editor.flight_camera, flight_look_x, flight_look_y)
                    if input_action_pressed(.Camera_Reset) {
                        chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
                    }
                }
                control := postale_game.Control {
                    throttle_up   = canvas2d.IsKeyDown(.LEFT_SHIFT) || canvas2d.IsKeyDown(.RIGHT_SHIFT),
                    throttle_down = control_key_down(),
                }
                if canvas2d.IsKeyDown(.S) do control.pitch += 1
                if canvas2d.IsKeyDown(.W) do control.pitch -= 1
                if canvas2d.IsKeyDown(.D) do control.roll += 1
                if canvas2d.IsKeyDown(.A) do control.roll -= 1
                if canvas2d.IsKeyDown(.E) do control.yaw += 1
                if canvas2d.IsKeyDown(.Q) do control.yaw -= 1
                if canvas2d.GamepadAvailable() {
                    control.pitch = stronger_axis(control.pitch, gamepad_axis(.Left_Y))
                    control.roll = stronger_axis(control.roll, gamepad_axis(.Left_X))
                    if gamepad_down(.Right_Shoulder) do control.yaw += 1
                    if gamepad_down(.Left_Shoulder) do control.yaw -= 1
                    control.throttle_up = control.throttle_up || gamepad_axis(.Right_Trigger) > 0
                    control.throttle_down = control.throttle_down || gamepad_axis(.Left_Trigger) > 0
                }
                if editor.gameplay_options.invert_flight_pitch do control.pitch = -control.pitch
                control.pitch = clamp(control.pitch, -1, 1)
                control.roll = clamp(control.roll, -1, 1)
                control.yaw = clamp(control.yaw, -1, 1)
                editor.flight_control = control
                editor.aircraft_fixed_accumulator = min(
                    editor.aircraft_fixed_accumulator + f64(delta_seconds),
                    AIRCRAFT_MAX_CATCH_UP,
                )
                for editor.aircraft_fixed_accumulator >= AIRCRAFT_FIXED_STEP {
                    body := active_aircraft_body(editor)
                    was_crashed := editor.postale.crashed
                    if editor.aircraft.active == .Rondine {
                        was_crashed = editor.rondine.crashed
                    } else if editor.aircraft.active != .Postale {
                        was_crashed = editor.libellula.crashed
                    }
                    impact_vertical_speed := max(-body.velocity.y, f32(0))
                    editor.aircraft_previous_body = body^
                    editor.aircraft_previous_body_valid = true
                    touchdown_speed := f32(
                        math.sqrt(f64(body.velocity.x * body.velocity.x + body.velocity.z * body.velocity.z)),
                    )
                    terrain_height := terrain.sample_surface_height(
                        &editor.project,
                        0,
                        body.position.x,
                        body.position.z,
                    )
                    ground := postale_game.drivable_surface_height(terrain_height, editor.project.sea_level)
                    ground = terrain.structure_collision_surface_height(
                        &editor.project,
                        body.position.x,
                        body.position.z,
                        ground,
                    )
                    if editor.aircraft.active == .Rondine {
                        local_wind := aircraft_local_airflow(editor, body)
                        rondine_game.step(&editor.rondine, {
                                throttle_up   = control.throttle_up,
                                throttle_down = control.throttle_down,
                                pitch         = control.pitch,
                                roll          = control.roll,
                                yaw           = control.yaw,
                            }, editor.project.sea_level, f32(AIRCRAFT_FIXED_STEP), local_wind)
                        if !rondine_footprint_is_clear_water(
                               editor,
                               editor.rondine.body.position,
                               flight.basis_from_orientation(editor.rondine.body.orientation),
                           ) &&
                           editor.rondine.telemetry.speed > 8 {
                            rondine_game.crash(&editor.rondine)
                        }
                    } else if editor.aircraft.active != .Postale {
                        local_wind := aircraft_local_airflow(editor, body)
                        libellula_game.step(&editor.libellula, {
                                throttle_up   = control.throttle_up,
                                throttle_down = control.throttle_down,
                                pitch         = control.pitch,
                                roll          = control.roll,
                                yaw           = control.yaw,
                            }, ground, f32(AIRCRAFT_FIXED_STEP), local_wind)
                    } else {
                        local_wind := aircraft_local_airflow(editor, body)
                        ground_result := postale_game.step(
                            &editor.postale,
                            control,
                            ground,
                            f32(AIRCRAFT_FIXED_STEP),
                            local_wind,
                        )
                        wheels_on_land := terrain_height >= editor.project.sea_level
                        if ground_result.touched_down && wheels_on_land {
                            editor.landing_wheel_squeal = max(
                                editor.landing_wheel_squeal,
                                clamp((touchdown_speed - 3) / 18, 0, 1),
                            )
                            editor.landing_wheel_speed = touchdown_speed
                        }
                        _ = markov_wreck_aircraft_collision_step(editor)
                    }
                    is_crashed := editor.postale.crashed
                    if editor.aircraft.active == .Rondine {
                        is_crashed = editor.rondine.crashed
                    } else if editor.aircraft.active != .Postale {
                        is_crashed = editor.libellula.crashed
                    }
                    if !was_crashed && is_crashed {
                        crash_recovery_begin(editor, {body.position.x, body.position.y, body.position.z})
                        crash_profile = engine_sound.Crash_Profile.Fixed_Wing
                        if editor.aircraft.active == .Libellula || editor.aircraft.active == .Libellula_Mk2 {
                            crash_profile = engine_sound.Crash_Profile.Rotorcraft
                        }
                        crash_severity = max(
                            crash_severity,
                            clamp(impact_vertical_speed / 18 + touchdown_speed / 75, .2, 1),
                        )
                        crash_slide_speed = clamp(touchdown_speed / 60, 0, 1)
                        dust_surface, _ := road_car_surface(
                            editor,
                            {body.position.x, body.position.y, body.position.z},
                        )
                        crash_surface = crash_surface_from_dust(dust_surface)
                        crash_water_mix = 0
                        if terrain_height < editor.project.sea_level {
                            crash_water_mix = 1
                        }
                    }
                    editor.aircraft_fixed_accumulator -= AIRCRAFT_FIXED_STEP
                }
                left_tip, right_tip, trail_basis, wing_trails_available := active_aircraft_wing_trail_anchors(editor)
                wing_trails_emitting :=
                    wing_trails_available && !active_aircraft_grounded(editor) && !active_aircraft_crashed(editor)
                if !wing_trails_emitting && editor.wing_trails.count > 0 {
                    // Keep previously emitted vapor advancing after a
                    // vehicle switch, touchdown, or crash, but feed zero
                    // airflow so no new fixed-wing trails can spawn.
                    body := active_aircraft_body(editor)
                    left_tip, right_tip = flight_to_world(body.position), flight_to_world(body.position)
                    trail_basis = flight.basis_from_orientation(body.orientation)
                }
                if wing_trails_emitting || editor.wing_trails.count > 0 {
                    body := active_aircraft_body(editor)
                    trail_airspeed := wing_trails_emitting ? active_aircraft_apparent_airflow_speed(editor) : f32(0)
                    trail_local := atmosphere.sample_at(
                        &editor.atmosphere,
                        {body.position.x, body.position.y, body.position.z},
                        body.position.y,
                    )
                    particle_systems.step_wing_trails(
                        &editor.wing_trails,
                        min(delta_seconds, .05),
                        particle_systems.Vec3{left_tip.x, left_tip.y, left_tip.z},
                        particle_systems.Vec3{right_tip.x, right_tip.y, right_tip.z},
                        particle_systems.Vec3{trail_basis.forward.x, trail_basis.forward.y, trail_basis.forward.z},
                        particle_systems.Vec3{trail_basis.up.x, trail_basis.up.y, trail_basis.up.z},
                        particle_systems.Vec3{trail_local.wind[0], trail_local.wind[1], trail_local.wind[2]},
                        trail_airspeed,
                    )
                }
                vehicles.sync_driver(&editor.pilot)
                can_exit := postale_game.can_exit(&editor.postale)
                if editor.aircraft.active == .Rondine {
                    can_exit = rondine_game.can_exit(&editor.rondine)
                } else if editor.aircraft.active != .Postale {
                    can_exit = libellula_game.can_exit(&editor.libellula)
                }
                if input_action_pressed(.Interact) && can_exit {
                    if vehicles.try_exit(&editor.pilot, true) {
                        editor.bomber_mode = false
                        editor.flight_control = {}
                        player_place(editor, editor.pilot.position, .Vehicle_Exit, editor.pilot.facing_yaw_radians)
                        editor.camera = third_person.default_camera()
                    }
                }
                chase_camera.step(
                    &editor.flight_camera,
                    aircraft_camera_target(editor),
                    min(delta_seconds, .05),
                    max(postale_flyby_shake(editor), rondine_drift_shake(editor)),
                    aircraft_wind_buffet(editor),
                )
                editor.camera_pose = editor.flight_camera.pose
                if editor.bomber_mode {
                    editor.camera_pose = bomber_camera_pose(editor)
                }
            } else {
                editor.bomber_mode = false
                editor.aircraft_fixed_accumulator = 0
                editor.aircraft_previous_body_valid = false
            }
            if in_car {
                if input_action_pressed(.Interact) {
                    if vehicles.try_exit(&editor.pilot, true) {
                        player_place(editor, editor.pilot.position, .Vehicle_Exit, editor.pilot.facing_yaw_radians)
                        editor.camera = third_person.default_camera()
                    }
                } else {
                    control := car_controller_input()
                    if benchmark_mode && (benchmark_scenario == "road_grip" || benchmark_scenario == "terrain_grip") {
                        control.throttle = 1
                        control.steering = math.sin(f32(frame) * .032) * .72
                    }
                    dust_surface, drive_surface := road_car_surface(
                        editor,
                        {editor.car.position.x, editor.car.position.y, editor.car.position.z},
                    )
                    car_impact_severity, car_impact_slide_speed, car_impact_obliqueness, car_impact_pan :=
                        car_controller_step(editor, control, drive_surface, min(delta_seconds, .05), listener_yaw)
                    if car_impact_severity > 0 {
                        crash_severity = max(crash_severity, car_impact_severity)
                        crash_slide_speed = car_impact_slide_speed
                        crash_obliqueness = car_impact_obliqueness
                        crash_pan = car_impact_pan
                        crash_surface = crash_surface_from_dust(dust_surface)
                        crash_water_mix =
                            terrain.sample_surface(&editor.project, 0, editor.car.position.x, editor.car.position.z) == .Land ? 0 : 1
                    }
                    contacts := [4]particle_systems.Vehicle_Contact{}
                    for wheel, index in editor.car_wheels {
                        wheel_position := roads.Vec3{wheel.position[0], wheel.position[1], wheel.position[2]}
                        wheel_dust, _ := road_car_surface(editor, wheel_position)
                        wheel_ground := terrain.sample_surface_height(
                            &editor.project,
                            0,
                            wheel.position[0],
                            wheel.position[2],
                        )
                        contacts[index] = {
                            position = {wheel.position[0], wheel_ground, wheel.position[2]},
                            grounded = wheel.contact,
                            surface  = wheel_dust,
                        }
                    }
                    particle_systems.step_vehicle_effects(
                        &editor.vehicle_effects,
                        min(delta_seconds, .05),
                        vehicles.car_drive_speed(editor.car_drive),
                        editor.car_drive.steering,
                        control.handbrake,
                        editor.car_drive.slip_amount,
                        contacts,
                    )
                    vehicles.sync_driver(&editor.pilot)
                    speed_ratio := clamp(
                        vehicles.car_drive_speed(editor.car_drive) / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward,
                        0,
                        1,
                    )
                    // The chase still recenters behind the car, while the right
                    // stick gives the player a temporary look around it.
                    car_look_x := gamepad_axis(.Right_X)
                    if editor.gameplay_options.invert_look_x do car_look_x = -car_look_x
                    target_yaw := -math.PI * .5 - editor.car.yaw_radians + car_look_x * .85
                    editor.camera.yaw_radians = vehicles.car_drive_angle_step(
                        editor.camera.yaw_radians,
                        target_yaw,
                        clamp((3.8 + speed_ratio * 2.2) * min(delta_seconds, .05), 0, 1),
                    )
                    editor.camera.pitch_radians = clamp(.24 - gamepad_axis(.Right_Y) * .38, -.2, .75)
                    editor.camera.distance = 5.2 + speed_ratio * 1.8
                    editor.camera.height = 1.15 + speed_ratio * .32
                    desired_camera := third_person.camera_pose(editor.car.position, editor.camera)
                    editor.camera_pose = third_person.follow_camera(
                        editor.camera_pose,
                        desired_camera,
                        8,
                        min(delta_seconds, .05),
                    )
                }
            }
            // `driving` is the mode captured at the start of this frame. After
            // an exit, defer on-foot input until the next frame so the same F
            // press cannot immediately enter the nearby vehicle again.
            if editor.pilot.mode == .On_Foot && !driving {
                if !dialogue_was_open && !editor.attendant_dialogue_open {
                    town_wheel_interaction_consumed := town_mouse_wheel_gameplay_process(
                        editor,
                        min(delta_seconds, .05),
                    )
                    stick_look_x := gamepad_axis(.Right_X) * 180 * delta_seconds
                    stick_look_y := gamepad_axis(.Right_Y) * 180 * delta_seconds
                    if editor.gameplay_options.invert_look_x do stick_look_x = -stick_look_x
                    if editor.gameplay_options.invert_look_y do stick_look_y = -stick_look_y
                    third_person.look(
                        &editor.camera,
                        look_x + stick_look_x,
                        -look_y - stick_look_y,
                        editor.gameplay_options.look_sensitivity,
                    )
                    controller_zoom := (gamepad_axis(.Left_Trigger) - gamepad_axis(.Right_Trigger)) * 4 * delta_seconds
                    editor.camera.distance = clamp(
                        editor.camera.distance - canvas2d.GetMouseWheelMove() * .5 + controller_zoom,
                        3,
                        12,
                    )
                    move_x, move_y := f32(0), f32(0)
                    if canvas2d.IsKeyDown(.D) do move_x += 1
                    if canvas2d.IsKeyDown(.A) do move_x -= 1
                    if canvas2d.IsKeyDown(.W) do move_y += 1
                    if canvas2d.IsKeyDown(.S) do move_y -= 1
                    move_x = stronger_axis(move_x, gamepad_axis(.Left_X))
                    move_y = stronger_axis(move_y, -gamepad_axis(.Left_Y))
                    input := third_person.Input {
                        move_x             = move_x,
                        move_y             = move_y,
                        run_toggle_pressed = input_action_pressed(.Run),
                        jump_pressed       = input_action_pressed(.Jump),
                        jump_held          = input_action_down(.Jump),
                        grounded           = editor.player.grounded,
                        camera_yaw_radians = editor.camera.yaw_radians,
                        ground_normal      = editor.player.ground_normal,
                    }
                    frame_seconds := min(delta_seconds, .05)
                    stride_phase_before := editor.player_stride_phase
                    player_was_grounded := editor.player.grounded
                    player_horizontal_velocity_before := third_person.Vec3 {
                        editor.player.velocity.x,
                        0,
                        editor.player.velocity.z,
                    }
                    player_horizontal_speed_before := f32(
                        math.sqrt(
                            f64(
                                player_horizontal_velocity_before.x * player_horizontal_velocity_before.x +
                                player_horizontal_velocity_before.z * player_horizontal_velocity_before.z,
                            ),
                        ),
                    )
                    player_vertical_speed_before := editor.player.velocity.y
                    if !town_mouse_wheel_mounted {
                        third_person.step(
                            &editor.player,
                            input,
                            editor.tweak.player,
                            frame_seconds,
                            integrate_position = false,
                        )
                        _ = gameplay_physics_resolve_player(editor, frame_seconds)
                        if editor.player.position.y < editor.project.sea_level - PLAYER_FALL_RECOVERY_DEPTH {
                            crash_recovery_begin(editor, editor.player.position, .Tumble)
                        }
                    }
                    movement_intent := clamp(f32(math.sqrt(f64(move_x * move_x + move_y * move_y))), 0, 1)
                    mouse_emote_update(&editor.mouse_emote, {
                            movement_intent   = movement_intent,
                            horizontal_speed  = player_horizontal_speed_before,
                            grounded          = editor.player.grounded,
                            player_controlled = editor.pilot.mode == .On_Foot,
                            incompatible_pose = town_mouse_wheel_mounted,
                            paused            = pause_menu_is_open(editor),
                        }, frame_seconds)
                    player_animation_update(editor, frame_seconds)
                    player_horizontal_speed := f32(
                        math.sqrt(
                            f64(
                                editor.player.velocity.x * editor.player.velocity.x +
                                editor.player.velocity.z * editor.player.velocity.z,
                            ),
                        ),
                    )
                    empty_player_contacts: [4]particle_systems.Vehicle_Contact
                    particle_systems.step_vehicle_effects(
                        &editor.player_terrain_effects,
                        frame_seconds,
                        0,
                        0,
                        false,
                        0,
                        empty_player_contacts,
                    )
                    scrabble_strength :=
                        clamp((movement_intent - .70) / .30, 0, 1) * clamp((2.2 - player_horizontal_speed) / 1.7, 0, 1)
                    if editor.player.grounded && scrabble_strength > 0 {
                        intent_direction := particle_systems.Vec3 {
                            -math.sin(editor.player.facing_yaw_radians),
                            0,
                            -math.cos(editor.player.facing_yaw_radians),
                        }
                        dust_surface, _ := road_car_surface(
                            editor,
                            {editor.player.position.x, editor.player.position.y, editor.player.position.z},
                        )
                        ground_y := terrain.sample_surface_height(
                            &editor.project,
                            0,
                            editor.player.position.x,
                            editor.player.position.z,
                        )
                        particle_systems.spawn_scrabble(&editor.player_terrain_effects, frame_seconds, {
                                position = {
                                    editor.player.position.x - intent_direction.x * .34,
                                    ground_y,
                                    editor.player.position.z - intent_direction.z * .34,
                                },
                                grounded = true,
                                surface  = dust_surface,
                            }, intent_direction, scrabble_strength)
                    }
                    editor.player_stop_spray_cooldown = max(editor.player_stop_spray_cooldown - frame_seconds, f32(0))
                    if editor.player.grounded && player_horizontal_speed > .8 {
                        editor.player_stop_spray_speed = max(editor.player_stop_spray_speed, player_horizontal_speed)
                    }
                    stopped_suddenly :=
                        player_was_grounded &&
                        editor.player.grounded &&
                        player_horizontal_speed_before > .6 &&
                        player_horizontal_speed <= .6 &&
                        editor.player_stop_spray_speed > 3.2 &&
                        editor.player_stop_spray_cooldown <= 0
                    if stopped_suddenly {
                        travel_direction := particle_systems.Vec3 {
                            player_horizontal_velocity_before.x / player_horizontal_speed_before,
                            0,
                            player_horizontal_velocity_before.z / player_horizontal_speed_before,
                        }
                        dust_surface, _ := road_car_surface(
                            editor,
                            {editor.player.position.x, editor.player.position.y, editor.player.position.z},
                        )
                        ground_y := terrain.sample_surface_height(
                            &editor.project,
                            0,
                            editor.player.position.x,
                            editor.player.position.z,
                        )
                        particle_systems.spawn_stop_spray(&editor.player_terrain_effects, {
                                position = {
                                    editor.player.position.x - travel_direction.x * .48,
                                    ground_y,
                                    editor.player.position.z - travel_direction.z * .48,
                                },
                                grounded = true,
                                surface  = dust_surface,
                            }, travel_direction, clamp(editor.player_stop_spray_speed / 10, .35, 1))
                        editor.player_stop_spray_cooldown = .28
                        editor.player_stop_spray_speed = 0
                    } else if player_horizontal_speed <= .08 {
                        editor.player_stop_spray_speed = 0
                    }
                    if editor.player.grounded &&
                       player_horizontal_speed > .12 &&
                       engine_sound.footstep_phase_crossed(stride_phase_before, editor.player_stride_phase) {
                        footstep_triggered = true
                        footstep_intensity = clamp(
                            .2 +
                            player_horizontal_speed /
                                max(editor.tweak.player_animation.bound_full_speed, f32(.1)) *
                                .8,
                            .2,
                            1,
                        )
                    }
                    if !player_was_grounded && editor.player.grounded && player_vertical_speed_before < -.5 {
                        footstep_triggered = true
                        footstep_landing = true
                        footstep_intensity = clamp((-player_vertical_speed_before - .5) / 7, .35, 1)
                        footstep_slide = clamp(
                            player_horizontal_speed / max(editor.tweak.player_animation.bound_full_speed, f32(.1)),
                            0,
                            1,
                        )
                    }
                    if footstep_triggered {
                        dust_surface, _ := road_car_surface(
                            editor,
                            {editor.player.position.x, editor.player.position.y, editor.player.position.z},
                        )
                        footstep_surface = footstep_surface_from_dust(dust_surface)
                    }
                    player_tail_update(editor, frame_seconds)
                    editor.pilot.position = editor.player.position
                    editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
                    if input_action_pressed(.Interact) &&
                       !town_wheel_interaction_consumed &&
                       !town_mouse_wheel_mounted {
                        dockmaster_interacted := open_markov_marina_dockmaster_dialogue(editor)
                        marin_interacted := !dockmaster_interacted && open_marin_dialogue(editor)
                        resident, _, story_near := nearest_story_resident(editor, require_action = true)
                        story_interacted :=
                            !dockmaster_interacted &&
                            !marin_interacted &&
                            story_near &&
                            open_story_dialogue(editor, resident)
                        trailer_interacted := false
                        entered := false
                        if !dockmaster_interacted && !marin_interacted && !story_interacted {
                            trailer_interacted = car_trailer_interact(editor)
                        }
                        if !dockmaster_interacted && !marin_interacted && !story_interacted && !trailer_interacted {
                            _, entered = vehicles.try_enter_nearest(
                                &editor.pilot,
                                []^vehicles.Vehicle{&editor.car, active_aircraft_vehicle(editor)},
                            )
                        }
                        if entered {
                            editor.player.running = false
                            editor.flight_control = {}
                            if driving_aircraft(editor) {
                                chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
                            }
                        } else if !dockmaster_interacted &&
                           !marin_interacted &&
                           !story_interacted &&
                           !trailer_interacted &&
                           libellula_attendant_near(editor) {
                            attendant, _, attendant_near := nearest_service_attendant(editor)
                            if attendant_near do open_attendant_dialogue(editor, attendant)
                        }
                    }
                    if editor.camera_target_lock {
                        editor.camera_pose = third_person.camera_near(editor.libellula.vehicle.position, {8, 5, 8})
                    } else {
                        desired_camera := third_person.camera_pose(editor.player.position, editor.camera)
                        editor.camera_pose = third_person.follow_camera(
                            editor.camera_pose,
                            desired_camera,
                            12,
                            min(delta_seconds, .05),
                        )
                    }
                }
            }
        }
    }
    mouse_gait_lab_physics_step(editor, simulation_delta)
    gameplay_physics_step_world(editor, simulation_delta)
    player_paws_step(editor, simulation_delta)
    if !run_frame_finish_world_simulation(run, frame_state) do return false
    return true
}
