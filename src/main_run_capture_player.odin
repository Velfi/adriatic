#+feature using-stmt
package main

import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:math"

run_prepare_player_capture :: proc(editor: ^Editor, using config: ^Run_Config) {
    if capture_target == "player" ||
       capture_target == "player-front" ||
       capture_target == "player-three-quarter" ||
       capture_target == "player-profile" ||
       capture_target == "player-walk" ||
       capture_target == "player-run-compress" ||
       capture_target == "player-turn-left" ||
       capture_target == "player-turn-right" ||
       capture_target == "player-brake" ||
       capture_target == "player-jump" ||
       capture_target == "player-fall" ||
       capture_target == "player-blink" ||
       capture_target == "player-posted" ||
       capture_target == "player-customization" ||
       capture_target == "player-hat-acorn" ||
       capture_target == "player-hat-acorn-front" ||
       capture_target == "player-hat-acorn-profile" ||
       capture_target == "player-hat-bottle-cap" ||
       capture_target == "player-hat-bottle-cap-front" ||
       capture_target == "player-hat-bottle-cap-profile" ||
       capture_target == "player-hat-bottle-cap-top" ||
       capture_target == "player-hat-paper-boat" ||
       capture_target == "player-hat-chef" ||
       capture_target == "player-hat-ushanka" ||
       capture_target == "player-hat-ushanka-three-quarter" ||
       capture_target == "player-hat-ushanka-profile" ||
       capture_target == "player-hat-beret" ||
       capture_target == "player-hat-beret-front" ||
       capture_target == "player-hat-beret-profile" ||
       capture_target == "player-hat-beret-walk" ||
       capture_target == "player-hat-beret-turn-left" ||
       capture_target == "player-hat-alpine" ||
       capture_target == "player-hat-alpine-front" ||
       capture_target == "player-hat-alpine-profile" ||
       capture_target == "player-hat-flat-cap" ||
       capture_target == "player-hat-flat-cap-front" ||
       capture_target == "player-hat-flat-cap-three-quarter" ||
       capture_target == "player-hat-flat-cap-profile" ||
       capture_target == "player-hat-sailor" ||
       capture_target == "player-hat-sailor-front" ||
       capture_target == "player-hat-sailor-profile" {
        editor.camera_target_lock = false
        editor.postale_visible = false
        editor.libellula_visible = false
        editor.player.position.x += 24
        editor.player.position.z += 20
        editor.player.position.y = terrain.sample_surface_height(
            &editor.project,
            0,
            editor.player.position.x,
            editor.player.position.z,
        )
        editor.pilot.position = editor.player.position
        editor.player.facing_yaw_radians = -.70
        editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
        editor.capture_player_walk_pose = capture_target == "player-walk" || capture_target == "player-hat-beret-walk"
        editor.capture_player_run_compress_pose = capture_target == "player-run-compress"
        editor.capture_player_turn_left_pose =
            capture_target == "player-turn-left" || capture_target == "player-hat-beret-turn-left"
        editor.capture_player_turn_right_pose = capture_target == "player-turn-right"
        editor.capture_player_brake_pose = capture_target == "player-brake"
        editor.capture_player_jump_pose = capture_target == "player-jump"
        editor.capture_player_fall_pose = capture_target == "player-fall"
        editor.capture_player_blink_pose = capture_target == "player-blink"
        editor.capture_player_posted_pose = capture_target == "player-posted"
        if capture_target == "player-customization" ||
           capture_target == "player-hat-acorn" ||
           capture_target == "player-hat-acorn-front" ||
           capture_target == "player-hat-acorn-profile" ||
           capture_target == "player-hat-bottle-cap" ||
           capture_target == "player-hat-bottle-cap-front" ||
           capture_target == "player-hat-bottle-cap-profile" ||
           capture_target == "player-hat-bottle-cap-top" ||
           capture_target == "player-hat-paper-boat" ||
           capture_target == "player-hat-chef" ||
           capture_target == "player-hat-ushanka" ||
           capture_target == "player-hat-ushanka-three-quarter" ||
           capture_target == "player-hat-ushanka-profile" ||
           capture_target == "player-hat-beret" ||
           capture_target == "player-hat-beret-front" ||
           capture_target == "player-hat-beret-profile" ||
           capture_target == "player-hat-beret-walk" ||
           capture_target == "player-hat-beret-turn-left" ||
           capture_target == "player-hat-alpine" ||
           capture_target == "player-hat-alpine-front" ||
           capture_target == "player-hat-alpine-profile" ||
           capture_target == "player-hat-flat-cap" ||
           capture_target == "player-hat-flat-cap-front" ||
           capture_target == "player-hat-flat-cap-three-quarter" ||
           capture_target == "player-hat-flat-cap-profile" ||
           capture_target == "player-hat-sailor" ||
           capture_target == "player-hat-sailor-front" ||
           capture_target == "player-hat-sailor-profile" {
            editor.mouse_fur = .Silver
            editor.mouse_pattern = .Piebald
            switch capture_target {
            case "player-hat-acorn", "player-hat-acorn-front", "player-hat-acorn-profile":
                editor.mouse_headgear = .Acorn_Cap
            case "player-hat-bottle-cap",
                 "player-hat-bottle-cap-front",
                 "player-hat-bottle-cap-profile",
                 "player-hat-bottle-cap-top":
                editor.mouse_headgear = .Bottle_Cap
            case "player-hat-paper-boat":
                editor.mouse_headgear = .Paper_Boat
            case "player-hat-ushanka", "player-hat-ushanka-three-quarter", "player-hat-ushanka-profile":
                editor.mouse_headgear = .Ushanka
            case "player-hat-beret",
                 "player-hat-beret-front",
                 "player-hat-beret-profile",
                 "player-hat-beret-walk",
                 "player-hat-beret-turn-left":
                editor.mouse_headgear = .Beret
            case "player-hat-alpine", "player-hat-alpine-front", "player-hat-alpine-profile":
                editor.mouse_headgear = .Alpine_Hat
            case "player-hat-flat-cap",
                 "player-hat-flat-cap-front",
                 "player-hat-flat-cap-three-quarter",
                 "player-hat-flat-cap-profile":
                editor.mouse_headgear = .Flat_Cap
            case "player-hat-sailor", "player-hat-sailor-front", "player-hat-sailor-profile":
                editor.mouse_headgear = .Sailor_Hat
            case:
                editor.mouse_headgear = .Chef_Hat
            }
        }
        if editor.capture_player_jump_pose || editor.capture_player_fall_pose {
            editor.player.position.y += .42
            editor.player.velocity.y = editor.capture_player_jump_pose ? f32(3.2) : f32(-3.2)
            editor.player.grounded = false
            editor.pilot.position = editor.player.position
        }
        capture_forward := third_person.Vec3 {
            -math.sin(editor.player.facing_yaw_radians),
            0,
            -math.cos(editor.player.facing_yaw_radians),
        }
        capture_run_pose :=
            capture_target == "player-walk" ||
            capture_target == "player-run-compress" ||
            capture_target == "player-hat-beret-walk"
        capture_posted_pose := capture_target == "player-posted"
        capture_front_view :=
            capture_target == "player-front" ||
            capture_target == "player-hat-acorn-front" ||
            capture_target == "player-hat-bottle-cap-front" ||
            capture_target == "player-hat-beret-front" ||
            capture_target == "player-hat-alpine-front" ||
            capture_target == "player-hat-flat-cap-front" ||
            capture_target == "player-hat-sailor-front"
        capture_three_quarter_view :=
            capture_target == "player-three-quarter" ||
            capture_target == "player-hat-ushanka-three-quarter" ||
            capture_target == "player-hat-flat-cap-three-quarter"
        capture_profile_view :=
            capture_target == "player-profile" ||
            capture_target == "player-hat-acorn-profile" ||
            capture_target == "player-hat-bottle-cap-profile" ||
            capture_target == "player-hat-ushanka-profile" ||
            capture_target == "player-hat-beret-profile" ||
            capture_target == "player-hat-alpine-profile" ||
            capture_target == "player-hat-flat-cap-profile" ||
            capture_target == "player-hat-sailor-profile"
        capture_top_view := capture_target == "player-hat-bottle-cap-top"
        // Track the moving profile from its longitudinal center so the
        // body and body-length tail share one depth plane in the capture.
        capture_front_distance := capture_run_pose ? f32(-.45) : (capture_posted_pose ? f32(1.32) : f32(1.95))
        capture_side_distance := capture_run_pose ? f32(2.45) : (capture_posted_pose ? f32(1.20) : f32(.40))
        if capture_front_view {
            capture_front_distance = 1.95
            capture_side_distance = 0
        }
        if capture_three_quarter_view {
            capture_front_distance = 1.72
            capture_side_distance = .92
        }
        if capture_profile_view {
            capture_front_distance = 0
            capture_side_distance = 1.95
        }
        capture_height := capture_run_pose ? f32(.62) : (capture_posted_pose ? f32(.90) : f32(.78))
        inspection_pose := third_person.Camera_Pose {
            position = {
                editor.player.position.x +
                capture_forward.x * capture_front_distance +
                capture_forward.z * capture_side_distance,
                editor.player.position.y + capture_height,
                editor.player.position.z +
                capture_forward.z * capture_front_distance -
                capture_forward.x * capture_side_distance,
            },
            target   = {
                editor.player.position.x - capture_forward.x * (capture_run_pose ? f32(.52) : f32(.18)),
                editor.player.position.y + (capture_posted_pose ? f32(.48) : f32(.34)),
                editor.player.position.z - capture_forward.z * (capture_run_pose ? f32(.52) : f32(.18)),
            },
        }
        if capture_top_view {
            // A slightly oblique overhead view avoids the camera-up
            // singularity while keeping the printed crown face dominant.
            inspection_pose.position = {
                editor.player.position.x - capture_forward.x * .22,
                editor.player.position.y + 2.05,
                editor.player.position.z - capture_forward.z * .22,
            }
            inspection_pose.target = {
                editor.player.position.x,
                editor.player.position.y + .54,
                editor.player.position.z,
            }
        }
        third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
        editor.camera_pose = inspection_pose
    }
}
