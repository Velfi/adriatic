#+feature using-stmt
package main

import dialogue "../packages/dialogue"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import canvas2d "zelda_engine:canvas2d"

run_prepare_vehicle_and_marta_capture :: proc(editor: ^Editor, using config: ^Run_Config) {
    if capture_car_mode && !capture_lab_mode {
        car := car_spawn_position(editor)
        editor.player.position = {car.x + 100, car.y, car.z + 100}
        editor.pilot.position = editor.player.position
        editor.camera_pose = {
            position = {car.x - 7.5, car.y + 4.6, car.z + 7.5},
            target   = {car.x, car.y + .65, car.z},
        }
    }
    if !capture_vehicle_showcase_mode && capture_target == "libellula" {
        editor.camera_target_lock = true
        // Keep the deterministic model-inspection capture focused on the
        // Libellula instead of allowing the default car and Postale spawns
        // to overlap its suspension and landing gear.
        editor.postale_visible = false
        editor.car.position.x += 100
        editor.car.position.z += 100
        editor.player.position = {
            editor.libellula.vehicle.position.x + 12,
            terrain.sample_surface_height(
                &editor.project,
                0,
                editor.libellula.vehicle.position.x + 12,
                editor.libellula.vehicle.position.z + 12,
            ),
            editor.libellula.vehicle.position.z + 12,
        }
        editor.pilot.position = editor.player.position
        inspection_pose := third_person.camera_near(editor.libellula.vehicle.position, {6, 3.5, 6})
        third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        editor.camera_pose = inspection_pose
        if request != nil && request.emote_name != "" {
            emote, emote_ok := mouse_emote_from_name(request.emote_name)
            if emote_ok {
                emote_target := Mouse_Emote_Target{}
                if request.emote_target_set {
                    emote_target = {
                        position    = {request.emote_target[0], request.emote_target[1], request.emote_target[2]},
                        valid       = true,
                        world_space = true,
                    }
                }
                _ = mouse_emote_start(
                    &editor.mouse_emote,
                    emote,
                    request.emote_handedness,
                    emote_target,
                    request.emote_seed,
                )
                editor.mouse_emote.frozen = true
                editor.mouse_emote.scrub_enabled = true
                editor.mouse_emote.scrub_normalized = request.emote_time_set ? request.emote_time : f32(.5)
                editor.mouse_emote.normalized_time = editor.mouse_emote.scrub_normalized
                editor.mouse_emote.blend_weight = 1
                if request.emote_headgear_set do editor.mouse_headgear = request.emote_headgear
                if request.emote_scarf_set do editor.mouse_scarf_enabled = request.emote_scarf
                if request.emote_mailbag_set do editor.capture_player_mailbag_hidden = !request.emote_mailbag
                if request.emote_ground_normal_set {
                    editor.player.ground_normal = {
                        request.emote_ground_normal[0],
                        request.emote_ground_normal[1],
                        request.emote_ground_normal[2],
                    }
                }
            }
        }
    }
    if !capture_vehicle_showcase_mode && capture_target == "postale" {
        editor.camera_target_lock = true
        postale_position := third_person.Vec3 {
            editor.postale.body.position.x,
            editor.postale.body.position.y,
            editor.postale.body.position.z,
        }
        editor.player.position = {
            postale_position.x + 12,
            terrain.sample_surface_height(&editor.project, 0, postale_position.x + 12, postale_position.z + 12),
            postale_position.z + 12,
        }
        editor.pilot.position = editor.player.position
        inspection_pose := third_person.camera_near(postale_position, {4.5, 2.6, 4.5})
        third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        editor.camera_pose = inspection_pose
    }
    if !capture_vehicle_showcase_mode &&
       (capture_target == "marta" ||
               capture_target == "gerta" ||
               capture_target == "marta-dialogue" ||
               capture_target == "marta-dialogue-magneto" ||
               capture_target == "marta-dialogue-return" ||
               capture_target == "marta-dialogue-memory" ||
               capture_target == "marta-dialogue-news" ||
               capture_target == "marta-dialogue-unicode" ||
               capture_target == "marta-dialogue-dark" ||
               capture_target == "gerta-dialogue" ||
               capture_target == "gerta-dialogue-magneto") {
        editor.camera_target_lock = false
        editor.postale_visible = false
        gerta_capture :=
            capture_target == "gerta" ||
            capture_target == "gerta-dialogue" ||
            capture_target == "gerta-dialogue-magneto"
        attendant_anchor := gerta_capture ? editor.gerta_position : editor.attendant_position
        attendant := airport_service_position(attendant_anchor)
        editor.player.position = {
            attendant.x + 20,
            terrain.sample_surface_height(&editor.project, 0, attendant.x + 20, attendant.z),
            attendant.z,
        }
        editor.pilot.position = editor.player.position
        // Dialogue captures render through the in-map presentation path.
        if capture_target == "marta-dialogue" ||
           capture_target == "marta-dialogue-magneto" ||
           capture_target == "marta-dialogue-return" ||
           capture_target == "marta-dialogue-memory" ||
           capture_target == "marta-dialogue-news" ||
           capture_target == "marta-dialogue-unicode" ||
           capture_target == "marta-dialogue-dark" ||
           capture_target == "gerta-dialogue" ||
           capture_target == "gerta-dialogue-magneto" {
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
        }
        inspection_pose := third_person.camera_near({attendant.x, attendant.y + .48, attendant.z}, {1.35, .62, 1.35})
        third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        editor.camera_pose = inspection_pose
        if capture_target == "marta-dialogue" ||
           capture_target == "marta-dialogue-magneto" ||
           capture_target == "marta-dialogue-return" ||
           capture_target == "marta-dialogue-memory" ||
           capture_target == "marta-dialogue-news" ||
           capture_target == "marta-dialogue-unicode" ||
           capture_target == "marta-dialogue-dark" ||
           capture_target == "gerta-dialogue" ||
           capture_target == "gerta-dialogue-magneto" {
            if capture_target == "marta-dialogue-memory" {
                editor.story_state.airfield_errand = .Completed
            } else if capture_target == "marta-dialogue-news" {
                editor.story_state.romance = .Together
            } else if capture_target == "gerta-dialogue-magneto" {
                _ = story.accept_airfield_errand(&editor.story_state)
            } else if capture_target == "marta-dialogue-return" {
                _ = story.accept_airfield_errand(&editor.story_state)
                _ = story.handoff_broken_magneto(&editor.story_state)
            }
            open_attendant_dialogue(editor, gerta_capture ? .Gerta : .Marta)
            if capture_target == "marta-dialogue-magneto" {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            } else if capture_target == "marta-dialogue-memory" {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            } else if capture_target == "gerta-dialogue-magneto" || capture_target == "marta-dialogue-return" {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            } else if capture_target == "marta-dialogue-news" {
                _ = dialogue.choose(&editor.attendant_dialogue, 3)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            } else if capture_target == "marta-dialogue-unicode" {
                _ = dialogue.choose(&editor.attendant_dialogue, 2)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            }
        }
    }
}
