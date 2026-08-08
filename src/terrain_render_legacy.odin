package main

import engine_sound "../packages/engine_sound"
import postale_game "../packages/postale"
import roads "../packages/roads"
import story "../packages/story"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:time"
import timezone "core:time/timezone"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"
import third_person "zelda_engine:third_person"

draw_terrain :: proc(editor: ^Editor, width, height: i32, time: f32) {
    // The depth-tested world pass has already drawn the game/editor scene.
    // Canvas commands from here onward are deliberately UI-only.
    canvas2d.ClearBackground({r = 104, g = 154, b = 181, a = 255})
    if menu_scene_current(editor) == .Customization do return
    if menu_scene_current(editor) == .Photo do return
    // Queue fixture notes with the rest of the Canvas UI, after whichever
    // scene-specific path below finishes building its overlay.
    defer fixture_notes_draw(editor, width, height)
    if editor.vehicle_paint_scene {
        vehicle_paint_draw(editor, width, height)
        return
    }
    if editor.vehicle_showcase_scene {
        // Vehicles and occupants are already rendered together in the
        // depth-tested world pass. Drawing a second canvas copy here would
        // cover occupants wherever they overlap the vehicle silhouette.
        return
    }
    if lab_scene_draw_ui(editor, width, height) do return
    draw_aircraft_speed_effects(editor, width, height, time)
    control_hint_draw_gameplay_hud(editor, width)
    bomber_hud_draw(editor, width, height)
    quest_tracking_hud_draw(editor, width)
    player_mail_notice_draw(editor, width)
    if editor.in_map {
        flying := driving_aircraft(editor)
        if flying && editor.gameplay_options.show_hud {
            body := active_aircraft_body(editor)
            ground := postale_game.drivable_surface_height(
                terrain.sample_surface_height(&editor.project, 0, body.position.x, body.position.z),
                editor.project.sea_level,
            )
            altitude := max(f32(0), body.position.y - ground - active_aircraft_ground_clearance(editor))
            draw_flight_instruments(editor, width, height, altitude)
        } else if editor.attendant_dialogue_open {
            dialogue_tv_draw(editor, width, height)
        } else if editor.gameplay_options.show_hud {
            if prompt := vehicle_entry_prompt(editor); prompt != nil {
                canvas2d.DrawRectangle(width / 2 - 116, height - 92, 232, 42, {8, 28, 45, 220})
                canvas2d.DrawTextEx(
                    canvas2d.Font{},
                    prompt,
                    {f32(width / 2 - 99), f32(height - 77)},
                    15,
                    1,
                    {245, 239, 192, 255},
                )
            }
        }
    }
    if !editor.in_map && !editor.capture_world_only {
        editor_ui_draw(editor, width, height)
    }
    friendship_notice_draw(editor, width)
}
