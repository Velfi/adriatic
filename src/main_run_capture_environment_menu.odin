#+feature using-stmt
package main

import atmosphere "../packages/atmosphere"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"

run_prepare_environment_and_menu_capture :: proc(editor: ^Editor, using config: ^Run_Config) {
    if capture_grass_wind_mode || capture_target == "grass" {
        editor.capture_world_only = true
        editor.postale_visible = false
        editor.libellula_visible = false
        editor.player.position.x += 24
        // Clear the runway and its shoulder so the full radial grass
        // population falloff is visible against uninterrupted terrain.
        editor.player.position.z += 60
        editor.player.position.y = terrain.sample_surface_height(
            &editor.project,
            0,
            editor.player.position.x,
            editor.player.position.z,
        )
        editor.pilot.position = editor.player.position
        grass_pose := third_person.camera_look_at(
            {editor.player.position.x + 8, editor.player.position.y + 1.65, editor.player.position.z + 15},
            {editor.player.position.x - 2, editor.player.position.y + .55, editor.player.position.z - 9},
        )
        third_person.camera_set_pose(&editor.cameras, .Inspection, grass_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        editor.camera_pose = grass_pose
    }
    if capture_target == "pause" do menu_scene_set(editor, .Pause)
    if capture_target == "scrapbook" {
        menu_scene_set(editor, .Scrapbook)
        scrapbook_init()
        scrapbook_focus = 1
    }
    if capture_target == "world-map" do menu_scene_set(editor, .World_Map)
    if capture_target == "world-map-weather" {
        menu_scene_set(editor, .World_Map)
        editor.world_select_weather = true
        atmosphere.set_weather_override(&editor.atmosphere, .Automatic)
        atmosphere.trigger_front(&editor.atmosphere)
        front := &editor.atmosphere.schedule.front
        editor.atmosphere.schedule.elapsed_seconds =
            front.start_seconds + (front.end_seconds - front.start_seconds) * .5
    }
    if capture_target == "options" do menu_scene_set(editor, .Options)
    if capture_target == "options-dark" {
        menu_scene_set(editor, .Options)
        editor.options_focus = 8
        editor.options_scroll_y = 370
        editor.gameplay_options.theme_mode = .Dark
        ui_theme_set_mode(.Dark)
    }
    if capture_target == "marta-dialogue-dark" {
        editor.gameplay_options.theme_mode = .Dark
        ui_theme_set_mode(.Dark)
    }
    if capture_target == "quest-log" || capture_target == "quest-log-480" {
        _ = story.begin_delivery(&editor.story_state)
        _ = story.complete_delivery(&editor.story_state, .Iva)
        quest_tracking_refresh(editor)
        menu_scene_set(editor, .Journal)
        editor.quest_log_tab = .Active
        editor.quest_log_focus = 0
        editor.quest_log_scroll = 0
    }
    if capture_target == "options-hdr" {
        menu_scene_set(editor, .Options)
        editor.options_focus = 7
        editor.options_scroll_y = 300
    }
    if capture_target == "customization" {
        menu_scene_set(editor, .Customization)
        editor.mouse_fur = .Russet
        editor.mouse_pattern = .Piebald
        editor.mouse_headgear = .Acorn_Cap
    }
    if capture_target == "options-240" {
        menu_scene_set(editor, .Options)
        editor.gameplay_options.crunchiness = .P240
        crunchiness_apply(editor.gameplay_options.crunchiness)
    }
}
