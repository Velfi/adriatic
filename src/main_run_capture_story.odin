#+feature using-stmt
package main

import dialogue "../packages/dialogue"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

run_prepare_story_capture :: proc(editor: ^Editor, using config: ^Run_Config) {
    if capture_target == "niko" ||
       capture_target == "niko-handoff" ||
       capture_target == "niko-repeat-handoff" ||
       capture_target == "niko-meeting" ||
       capture_target == "niko-together" ||
       capture_target == "iva" ||
       capture_target == "iva-handoff" ||
       capture_target == "iva-repeat-handoff" ||
       capture_target == "iva-together" ||
       capture_target == "bojan" ||
       capture_target == "bojan-inspect-choices" ||
       capture_target == "bojan-repair-payoff" ||
       capture_target == "bojan-repaired-check" ||
       capture_target == "zora" ||
       capture_target == "zora-choices" ||
       capture_target == "zora-reading" ||
       capture_target == "zora-recall" ||
       capture_target == "vesna-repeat" ||
       capture_target == "petar-repeat" ||
       capture_target == "anica-repeat" ||
       capture_target == "toma-post-handoff" ||
       capture_target == "toma-post-receipt-cycle2" ||
       capture_target == "lena-post-handoff" ||
       capture_target == "lena-post-receipt" {
        seed_default_island_towns(editor)
        resident := story.Resident.Niko
        switch capture_target {
        case "iva", "iva-handoff", "iva-repeat-handoff", "iva-together":
            resident = .Iva
        case "bojan", "bojan-inspect-choices", "bojan-repair-payoff", "bojan-repaired-check":
            resident = .Bojan
        case "zora", "zora-choices", "zora-reading", "zora-recall":
            resident = .Zora
        case "vesna-repeat":
            resident = .Vesna
        case "petar-repeat":
            resident = .Petar
        case "anica-repeat":
            resident = .Anica
        case "toma-post-handoff", "toma-post-receipt-cycle2":
            resident = .Toma
        case "lena-post-handoff", "lena-post-receipt":
            resident = .Lena
        }
        if capture_target == "niko-together" || capture_target == "iva-together" {
            editor.story_state.romance = .Together
            editor.story_state.repeat_deliveries = 2
        }
        if capture_target == "niko-repeat-handoff" {
            _ = story.accept_airfield_errand(&editor.story_state)
            _ = story.handoff_broken_magneto(&editor.story_state)
            _ = story.return_replacement_magneto(&editor.story_state)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Iva)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Niko)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Iva)
            _ = story.report_crash(&editor.story_state)
            _ = story.diagnose_crash(&editor.story_state)
            _ = story.apply_wing_patch(&editor.story_state)
            _ = story.verify_repair(&editor.story_state)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Niko)
            _ = story.complete_meeting(&editor.story_state)
        }
        if capture_target == "iva-repeat-handoff" {
            _ = story.accept_airfield_errand(&editor.story_state)
            _ = story.handoff_broken_magneto(&editor.story_state)
            _ = story.return_replacement_magneto(&editor.story_state)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Iva)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Niko)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Iva)
            _ = story.report_crash(&editor.story_state)
            _ = story.diagnose_crash(&editor.story_state)
            _ = story.apply_wing_patch(&editor.story_state)
            _ = story.verify_repair(&editor.story_state)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Niko)
            _ = story.complete_meeting(&editor.story_state)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Lena)
        }
        if capture_target == "niko-handoff" {
            _ = story.accept_airfield_errand(&editor.story_state)
            _ = story.handoff_broken_magneto(&editor.story_state)
            _ = story.return_replacement_magneto(&editor.story_state)
        } else if capture_target == "niko-meeting" {
            _ = story.accept_airfield_errand(&editor.story_state)
            _ = story.handoff_broken_magneto(&editor.story_state)
            _ = story.return_replacement_magneto(&editor.story_state)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Iva)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Niko)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Iva)
            _ = story.report_crash(&editor.story_state)
            _ = story.diagnose_crash(&editor.story_state)
            _ = story.apply_wing_patch(&editor.story_state)
            _ = story.verify_repair(&editor.story_state)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Niko)
        } else if capture_target == "iva-handoff" {
            _ = story.accept_airfield_errand(&editor.story_state)
            _ = story.handoff_broken_magneto(&editor.story_state)
            _ = story.return_replacement_magneto(&editor.story_state)
            _ = story.begin_delivery(&editor.story_state)
            _ = story.complete_delivery(&editor.story_state, .Iva)
        }
        position, found := world_story_resident_position(editor, resident)
        if found {
            editor.camera_target_lock = false
            editor.postale_visible = false
            editor.libellula_visible = false
            editor.player.position = {
                position.x + 20,
                terrain.sample_height(&editor.project, 0, position.x + 20, position.z),
                position.z,
            }
            editor.pilot.position = editor.player.position
            inspection_pose := third_person.camera_near({position.x, position.y + .48, position.z}, {1.35, .62, 1.35})
            third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
            third_person.camera_set_active(&editor.cameras, .Inspection)
            editor.camera_pose = inspection_pose
        }
        if capture_target == "zora-reading" || capture_target == "zora-recall" {
            // Dialogue captures render through the in-map presentation path.
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if open_story_dialogue(editor, .Zora) {
                if capture_target == "zora-recall" {
                    _ = dialogue.choose(&editor.attendant_dialogue, 0)
                    attendant_dialogue_definition_release(editor)
                    if open_story_dialogue(editor, .Zora) {
                        _ = dialogue.choose(&editor.attendant_dialogue, 0)
                        dialogue_view_reset(editor)
                        dialogue_view_complete_reveal(editor)
                    }
                } else {
                    _ = dialogue.choose(&editor.attendant_dialogue, 1)
                    dialogue_view_reset(editor)
                    dialogue_view_complete_reveal(editor)
                }
            }
        }
        if capture_target == "zora-choices" {
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            editor.story_state.tarot_readings = 0
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if open_story_dialogue(editor, .Zora) {
                dialogue_view_complete_reveal(editor)
            }
        }
        if capture_target == "lena-post-receipt" {
            // Exercise the actual recurring-delivery path so the captured
            // receipt reflects state after its completion effect.
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if story.begin_post_delivery(&editor.story_state) && open_story_dialogue(editor, .Lena) {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            }
        }
        if capture_target == "toma-post-receipt-cycle2" {
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            for _ in 0 ..< 5 {
                if !story.begin_post_delivery(&editor.story_state) do break
                recipient := editor.story_state.delivery.to
                if !story.complete_delivery(&editor.story_state, recipient) do break
            }
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if story.begin_post_delivery(&editor.story_state) && open_story_dialogue(editor, .Toma) {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
                _ = dialogue.choose(&editor.attendant_dialogue, 1)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            }
        }
        if capture_target == "toma-post-handoff" || capture_target == "lena-post-handoff" {
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            if capture_target == "lena-post-handoff" {
                editor.story_state.repeat_deliveries = 1
            }
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if open_story_dialogue(editor, resident) {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            }
        }
        if capture_target == "bojan-repaired-check" {
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            editor.story_state.repair = .Repaired
            editor.story_state.romance = .Together
            editor.story_state.repeat_deliveries = 2
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if open_story_dialogue(editor, .Bojan) {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            }
        }
        if capture_target == "bojan-inspect-choices" {
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            editor.story_state.repair = .Crash_Reported
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if open_story_dialogue(editor, .Bojan) {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            }
        }
        if capture_target == "bojan-repair-payoff" {
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            _ = story.accept_airfield_errand(&editor.story_state)
            _ = story.handoff_broken_magneto(&editor.story_state)
            _ = story.return_replacement_magneto(&editor.story_state)
            _ = story.report_crash(&editor.story_state)
            _ = story.diagnose_crash(&editor.story_state)
            _ = story.apply_wing_patch(&editor.story_state)
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if open_story_dialogue(editor, .Bojan) {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            }
        }
        if capture_target == "vesna-repeat" || capture_target == "petar-repeat" || capture_target == "anica-repeat" {
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            editor.story_state.clinic_visits =
                capture_target == "anica-repeat" ? 2 : capture_target == "petar-repeat" ? 4 : 3
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if open_story_dialogue(editor, resident) {
                dialogue_view_complete_reveal(editor)
            }
        }
        if capture_target == "niko-together" || capture_target == "iva-together" {
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if open_story_dialogue(editor, resident) {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            }
        }
        if capture_target == "niko-handoff" ||
           capture_target == "niko-repeat-handoff" ||
           capture_target == "niko-meeting" ||
           capture_target == "iva-handoff" ||
           capture_target == "iva-repeat-handoff" {
            if found {
                editor.player.position = {
                    position.x + 1.6,
                    terrain.sample_height(&editor.project, 0, position.x + 1.6, position.z),
                    position.z,
                }
                editor.player.facing_yaw_radians = math.atan2(
                    editor.player.position.x - position.x,
                    editor.player.position.z - position.z,
                )
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
            }
            editor.in_map = true
            editor.map_time = f32(canvas2d.GetTime())
            editor.player.grounded = true
            if open_story_dialogue(editor, resident) {
                _ = dialogue.choose(&editor.attendant_dialogue, 0)
                dialogue_view_reset(editor)
                dialogue_view_complete_reveal(editor)
            }
        }
    }
}
