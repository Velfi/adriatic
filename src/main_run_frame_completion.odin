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

run_frame_finish_capture_or_reload :: proc(using run: ^Run_State, using frame_state: ^Run_Frame_State) -> bool {
    // Player captures wait long enough for the Verlet tail and pose blends
    // to settle; frame two only showed the first few links as a short nub.
    if capture_mode && request != nil && request.plant_sheet_views {
        next_capture_frame := plant_sheet_view_index == 0 ? capture_frame : plant_sheet_last_capture_frame + 2
        if plant_sheet_view_index < 3 && frame >= next_capture_frame {
            names := [3]string{"front", "side", "top"}
            canvas2d.TakeScreenshot(fmt.ctprintf("%s/%s.png", capture_output, names[plant_sheet_view_index]))
            plant_sheet_last_capture_frame = frame
            plant_sheet_view_index += 1
        }
    } else if capture_mode && request != nil && request.seed_frames > 0 {
        next_capture_frame := seed_frame_index == 0 ? capture_frame : seed_last_capture_frame + 2
        if seed_frame_index < request.seed_frames && frame >= next_capture_frame {
            seed := request.seed_start + u64(seed_frame_index)
            canvas2d.TakeScreenshot(fmt.ctprintf("%s/seed-%d.png", capture_output, seed))
            seed_last_capture_frame = frame
            seed_frame_index += 1
            if seed_frame_index < request.seed_frames {
                plant_generator_seed = request.seed_start + u64(seed_frame_index)
                plant_generator_rebuild()
            }
        }
    } else if capture_mode && request != nil && request.sequence_frames > 0 {
        if sequence_frame_index < request.sequence_frames && frame >= capture_frame {
            canvas2d.TakeScreenshot(fmt.ctprintf("%s/frame-%06d.png", capture_output, sequence_frame_index))
            sequence_last_capture_frame = frame
            sequence_frame_index += 1
        }
    } else if capture_mode && request != nil && request.turntable_frames > 0 {
        next_capture_frame := capture_frame + turntable_frame_index * turntable_capture_stride
        if turntable_frame_index < request.turntable_frames && frame == next_capture_frame {
            canvas2d.TakeScreenshot(fmt.ctprintf("%s/frame-%03d.png", capture_output, turntable_frame_index))
            turntable_last_capture_frame = frame
            turntable_frame_index += 1
        }
    } else if capture_mode && frame == capture_frame {
        canvas2d.TakeScreenshot(fmt.ctprintf("%s", capture_output))
    }
    // Vulkan screenshot readback completes asynchronously; retain several
    // presented frames after the request so capture mode always writes its PNG.
    if capture_mode &&
       request != nil &&
       request.plant_sheet_views &&
       plant_sheet_view_index >= 3 &&
       frame >= plant_sheet_last_capture_frame + 12 {
        return false
    }
    if capture_mode &&
       request != nil &&
       request.seed_frames > 0 &&
       seed_frame_index >= request.seed_frames &&
       frame >= seed_last_capture_frame + 12 {
        return false
    }
    if capture_mode &&
       request != nil &&
       request.sequence_frames > 0 &&
       sequence_frame_index >= request.sequence_frames &&
       frame >= sequence_last_capture_frame + 1 {
        return false
    }
    if capture_mode &&
       request != nil &&
       request.turntable_frames > 0 &&
       turntable_frame_index >= request.turntable_frames &&
       frame >= turntable_last_capture_frame + 12 {
        return false
    }
    if capture_mode &&
       (request == nil ||
               (!request.plant_sheet_views &&
                       request.turntable_frames == 0 &&
                       request.sequence_frames == 0 &&
                       request.seed_frames == 0)) &&
       frame >= max(32, capture_frame + 12) {
        return false
    }
    if instrument_duration_seconds > 0 && canvas2d.GetTime() - instrument_started_at >= instrument_duration_seconds {
        if editor.flame_graph.history_count > 0 {
            last_order := editor.flame_graph.history_count - 1
            _ = dio.flame_graph_write_source_range(&editor.flame_graph, dio.FLAME_GRAPH_DUMP_PATH, 0, last_order)
            _ = dio.flame_graph_write_source_folded(&editor.flame_graph, dio.FLAME_GRAPH_DUMP_PATH, 0, last_order)
        }
        editor.quit_requested = true
    }
    if HOT_RELOAD && hot_reload_requested(hot_library_path, hot_library_mtime) {
        if !hot_state_save(editor, hot_state_path) {
            fmt.eprintln("adriatic hot reload could not save state")
            return false
        }
        reload_requested = true
        return false
    }
    frame += 1
    return true
}
