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

Run_Frame_State :: struct {
    benchmark_frame_start:                              f64,
    frame_delta:                                        f32,
    driving, dialogue_was_open:                         bool,
    width, height:                                      i32,
    simulation_delta, listener_yaw:                     f32,
    world_x, world_z:                                   f32,
    cursor_hit, ui_hit:                                 bool,
    crash_severity, crash_water_mix, crash_slide_speed: f32,
    crash_surface:                                      engine_sound.Crash_Surface,
    crash_profile:                                      engine_sound.Crash_Profile,
    crash_wetness, crash_obliqueness, crash_pan:        f32,
    footstep_triggered:                                 bool,
    footstep_intensity:                                 f32,
    footstep_surface:                                   engine_sound.Footstep_Surface,
    footstep_landing:                                   bool,
    footstep_slide:                                     f32,
    saved_aircraft_body:                                flight.Body_State,
}

Run_State :: struct {
    editor:                                                                                  ^Editor,
    request:                                                                                 ^Capture_Request,
    startup_timings:                                                                         Startup_Timings,
    first_start, benchmark_mode:                                                             bool,
    instrument_duration_seconds:                                                             f64,
    benchmark_scenario:                                                                      string,
    benchmark_warmup, benchmark_frames, benchmark_window_width, benchmark_window_height:     int,
    benchmark_world_width, benchmark_world_height:                                           int,
    interactive_lab_mode:                                                                    bool,
    capture_mode, capture_car_mode, capture_story_meeting_mode, capture_wildflower_lab_mode: bool,
    capture_target, capture_output:                                                          string,
    postcard:                                                                                canvas2d.Texture,
    wind_sound_state:                                                                        wind_audio.Runtime,
    wind_audio_ready:                                                                        bool,
    ocean_sound_state:                                                                       ocean_audio.Runtime,
    ocean_audio_ready:                                                                       bool,
    spray_sound_state:                                                                       spray_audio.Runtime,
    spray_audio_ready, engine_audio_ready:                                                   bool,
    map_path, map_source, hot_library_path, hot_state_path:                                  string,
    hot_library_mtime:                                                                       i64,
    capture_frame:                                                                           int,
    selector_capture_pose:                                                                   third_person.Camera_Pose,
    selector_capture_pose_set:                                                               bool,
    startup_timings_emitted:                                                                 bool,
    benchmark_samples:                                                                       [4096]f64,
    benchmark_sample_count:                                                                  int,
    instrument_started_at:                                                                   f64,
    turntable_frame_index, turntable_capture_stride:                                         int,
    turntable_last_capture_frame, sequence_frame_index, sequence_last_capture_frame:         int,
    seed_frame_index, seed_last_capture_frame:                                               int,
    plant_sheet_view_index, plant_sheet_last_capture_frame:                                  int,
    reload_requested:                                                                        bool,
    frame:                                                                                   int,
}


adriatic_frame_loop :: proc(using run: ^Run_State) {
    frame_state: Run_Frame_State
    for !canvas2d.WindowShouldClose() && !editor.quit_requested {
        run_frame_prepare_input(run, &frame_state)
        if !run_frame_simulate_gameplay(run, &frame_state) do break
        if !run_frame_present(run, &frame_state) do break
        if !run_frame_finish_capture_or_reload(run, &frame_state) do break
    }
}
