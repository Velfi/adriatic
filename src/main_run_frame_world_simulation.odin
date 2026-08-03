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

run_frame_finish_world_simulation :: proc(using run: ^Run_State, using frame_state: ^Run_Frame_State) -> bool {
    if editor.in_map && !editor.vehicle_showcase_scene && !editor.vehicle_paint_scene {
        trailer_ground := terrain.sample_surface_height(
            &editor.project,
            0,
            editor.car_trailer_position.x,
            editor.car_trailer_position.z,
        )
        vehicles.car_trailer_step(
            &editor.car_trailer,
            &editor.car_trailer_position,
            &editor.car_trailer_yaw,
            editor.car.position,
            editor.car.yaw_radians,
            editor.car_drive.yaw_rate,
            editor.car_drive.velocity,
            editor.car_trailer_attached,
            trailer_ground,
            min(frame_delta, .05),
        )
        if editor.car_trailer_attached {
            editor.car_drive.velocity.x += editor.car_trailer.reaction_force.x * min(frame_delta, .05)
            editor.car_drive.velocity.z += editor.car_trailer.reaction_force.z * min(frame_delta, .05)
            if editor.car_physics_vehicle != nil {
                physics.set_linear_velocity(
                    editor.car_physics_world,
                    physics.vehicle_body(editor.car_physics_vehicle),
                    {editor.car_drive.velocity.x, editor.car_drive.velocity.y, editor.car_drive.velocity.z},
                )
            }
        }
    }
    if editor.cameras.active != .Player {
        editor.camera_pose = third_person.camera_active_pose(&editor.cameras)
    }
    wildflower_effects_step(editor, simulation_delta)
    if capture_wildflower_lab_mode {
        wind := editor.atmosphere.weather.wind
        particle_systems.step_petals(
            &editor.petal_effects,
            min(frame_delta, .05),
            {editor.player.position.x + 1.1, editor.player.position.y, editor.player.position.z},
            {8, 0, 1.5},
            {wind[0], 0, wind[1]},
            1,
        )
    }
    if editor.in_map && !editor.vehicle_showcase_scene && !driving_aircraft(editor) {
        camera_ground := terrain.sample_surface_height(
            &editor.project,
            0,
            editor.camera_pose.position.x,
            editor.camera_pose.position.z,
        )
        editor.camera_pose = third_person.camera_above_height(editor.camera_pose, camera_ground, .35)
        // Settlement plan views intentionally start their collision ray on
        // authored ground and look almost straight down. Resolving that ray
        // collapses the overhead camera onto its target.
        if !editor.settlement_vertical_map && editor.cameras.active != .Inspection {
            editor.camera_pose = gameplay_physics_resolve_camera(editor, editor.camera_pose)
        }
    }
    if benchmark_mode && frame == benchmark_warmup {
        world_benchmark_static_counters_reset()
    }
    if benchmark_scenario == "terrain_edit" && frame >= benchmark_warmup {
        edit_frame := frame - benchmark_warmup
        if edit_frame == 0 do terrain_history_push_undo(editor)
        benchmark_terrain_edit_step(editor, edit_frame)
    }
    if benchmark_scenario == "formation_edit" && frame >= benchmark_warmup {
        benchmark_formation_edit_step(editor, frame - benchmark_warmup)
    }
    if benchmark_scenario == "land_flight" || benchmark_scenario == "land_flight_cold" {
        benchmark_land_flight_step(editor, frame)
    }
    if benchmark_scenario == "land_flight_cold" && frame >= benchmark_warmup {
        editor.benchmark_ground_grass_disabled = false
    }
    if !editor.in_map && editor.tool != .Structure && cursor_hit && !ui_hit {
        if canvas2d.IsMouseButtonPressed(.LEFT) || canvas2d.IsMouseButtonPressed(.RIGHT) {
            terrain_history_push_undo(editor)
        }
        stroke_strength := editor.strength * min(frame_delta, f32(.05)) * 4
        if canvas2d.IsMouseButtonDown(.LEFT) {
            terrain.apply_stroke_with_hardness(
                &editor.project,
                editor.tool,
                world_x,
                world_z,
                editor.radius,
                stroke_strength,
                1,
                editor.hardness,
            )
            world_terrain_changed(editor, world_x, world_z, editor.radius)
        }
        if canvas2d.IsMouseButtonDown(.RIGHT) {
            terrain.apply_stroke_with_hardness(
                &editor.project,
                editor.tool,
                world_x,
                world_z,
                editor.radius,
                stroke_strength,
                -1,
                editor.hardness,
            )
            world_terrain_changed(editor, world_x, world_z, editor.radius)
        }
    }
    if capture_story_meeting_mode &&
       frame == capture_frame &&
       len(capture_target) > 5 &&
       capture_target[:5] == "wipe-" {
        if !cinematic_wipe_capture_play(editor, capture_target) {
            fmt.eprintf("story meeting capture could not start transition %s\n", capture_target)
            return false
        }
    }
    cinematic_update(editor, simulation_delta)
    bomber_drop_step(editor, min(simulation_delta, f32(.05)))
    bomber_pip_update(editor, min(simulation_delta, f32(.05)))
    return true
}
