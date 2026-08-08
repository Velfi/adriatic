#+feature using-stmt
package main

import atmosphere "../packages/atmosphere"
import flight "../packages/flight"
import libellula_game "../packages/libellula"
import postale_game "../packages/postale"
import roads "../packages/roads"
import rondine_game "../packages/rondine"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import third_person "zelda_engine:third_person"

run_prepare_showcase :: proc(editor: ^Editor, using config: ^Run_Config) -> bool {
    if vehicle_showcase_mode {
        target := showcase_target
        if target == "" do target = "postale"
        showcase_view := target
        car_orbit_degrees := 0
        car_orbit_view := false
        car_orbit_prefix := "car-orbit-"
        if len(target) > len(car_orbit_prefix) && target[:len(car_orbit_prefix)] == car_orbit_prefix {
            parsed, ok := strconv.parse_int(target[len(car_orbit_prefix):])
            if ok && parsed >= 0 && parsed < 360 {
                car_orbit_degrees = parsed
                car_orbit_view = true
                target = "car"
            }
        }
        if target == "postale-overhead" || target == "postale-overhead-front" || target == "postale-overhead-rear" {
            target = "postale"
        }
        if target == "rondine-drift" || target == "rondine-overhead" do target = "rondine"
        if target == "car-steer-left" ||
           target == "car-steer-right" ||
           target == "car-brake" ||
           target == "car-front" ||
           target == "car-rear" ||
           target == "car-brake-rear" {
            target = "car"
        }
        if target != "postale" &&
           target != "libellula" &&
           target != "libellula-mk2" &&
           target != "rondine" &&
           target != "car" {
            fmt.eprintf(
                "vehicle showcase target must be postale, postale-overhead[-front|-rear], libellula, libellula-mk2, rondine[-drift|-overhead], car, car-steer-left, car-steer-right, car-brake, car-front, car-rear, car-brake-rear, or car-orbit-<0..359>\n",
            )
            return false
        }
        editor.vehicle_showcase_scene = true
        editor.vehicle_showcase_target = target
        editor.in_map = true
        editor.map_time = 0
        if target == "postale" do editor.aircraft.active = .Postale
        if target == "libellula" do editor.aircraft.active = .Libellula
        if target == "libellula-mk2" do editor.aircraft.active = .Libellula_Mk2
        if target == "rondine" do editor.aircraft.active = .Rondine
        editor.postale_visible = target == "postale"
        editor.libellula_visible = target == "libellula" || target == "libellula-mk2"
        editor.rondine_visible = target == "rondine"
        editor.libellula.vehicle.locked = false
        editor.rondine.vehicle.locked = false
        editor.postale.body.position = {0, postale_game.GROUND_CLEARANCE, 0}
        editor.postale.vehicle.position = {0, postale_game.GROUND_CLEARANCE, 0}
        editor.libellula.body.position = {0, libellula_game.GROUND_CLEARANCE, 0}
        editor.libellula.vehicle.position = {0, libellula_game.GROUND_CLEARANCE, 0}
        editor.rondine.spawn_position = {0, rondine_game.GROUND_CLEARANCE, 0}
        rondine_game.reset(&editor.rondine, 0)
        editor.car.position = {}
        editor.car.yaw_radians = -math.PI * .5
        // Default showcase framing: aligned with the vehicle's forward axis,
        // with a modest elevation for the isometric presentation.
        editor.camera = {
            yaw_radians   = -math.PI * .38,
            pitch_radians = .18,
            distance      = 6.2,
            height        = 1,
        }
        if target == "rondine" {
            editor.camera.distance = 16
            editor.camera.height = 1.4
        }
        editor.pilot.position = {}
        if target == "postale" do editor.pilot.position.y = postale_game.GROUND_CLEARANCE
        if target == "libellula" || target == "libellula-mk2" do editor.pilot.position.y = libellula_game.GROUND_CLEARANCE
        if target == "rondine" do editor.pilot.position.y = rondine_game.GROUND_CLEARANCE
        editor.pilot.mode = .On_Foot
        editor.pilot.vehicle = nil
        if target == "postale" {
            _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.postale.vehicle})
            if !entered do return false
            switch showcase_view {
            case "postale-overhead":
                // A tiny longitudinal offset keeps the camera basis stable
                // while remaining visually indistinguishable from a true
                // orthographic-style plan view.
                editor.camera_pose = third_person.camera_look_at({.01, 8.2, .35}, {0, .15, 0})
            case "postale-overhead-front":
                editor.camera_pose = third_person.camera_look_at({0, 7.5, -3.0}, {0, .15, 0})
            case "postale-overhead-rear":
                editor.camera_pose = third_person.camera_look_at({0, 7.5, 3.0}, {0, .15, 0})
            case:
                editor.camera_pose = third_person.camera_look_at({10.5, 5.7, 10.5}, {0, .45, 0})
            }
        } else if target == "libellula" || target == "libellula-mk2" {
            _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.libellula.vehicle})
            if !entered do return false
            editor.camera_pose = third_person.camera_look_at({6, 5.8, 10}, {0, 1.2, 0})
        } else if target == "rondine" {
            if showcase_view == "rondine-drift" {
                for _ in 0 ..< 720 {
                    rondine_game.step(&editor.rondine, {throttle_up = true, roll = .82}, 0, 1.0 / 120.0)
                }
                // Preserve the staged turn, telemetry, and wake, but do not
                // let the showcase vehicle outrun its deliberately composed
                // camera while the capture frames settle.
                editor.rondine.body.velocity = {}
                editor.rondine.body.angular_velocity_world = {}
            }
            editor.pilot.position = editor.rondine.vehicle.position
            _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.rondine.vehicle})
            if !entered do return false
            p := editor.rondine.body.position
            basis := flight.basis_from_orientation(editor.rondine.body.orientation)
            forward := basis.forward
            right := basis.right
            if showcase_view == "rondine-overhead" {
                editor.camera_pose = third_person.camera_look_at({p.x + .01, p.y + 24, p.z - .12}, {p.x, p.y, p.z})
            } else if showcase_view == "rondine-drift" {
                editor.camera_pose = third_person.camera_look_at(
                    {p.x - forward.x * 18 + right.x * 7, p.y + 8, p.z - forward.z * 18 + right.z * 7},
                    {p.x - forward.x * 4.5, editor.project.sea_level + .35, p.z - forward.z * 4.5},
                )
            } else {
                editor.camera_pose = third_person.camera_look_at(
                    {p.x + forward.x * 13 + right.x * 6, p.y + 5.8, p.z + forward.z * 13 + right.z * 6},
                    {p.x + forward.x, p.y + .45, p.z + forward.z},
                )
            }
        } else {
            _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.car})
            if !entered do return false
            switch showcase_view {
            case "car-steer-left":
                editor.car_drive.steering = -1
            case "car-steer-right":
                editor.car_drive.steering = 1
            case "car-brake", "car-brake-rear":
                editor.car_drive.acceleration_feedback = -1
                editor.car_drive.handbrake_amount = 1
            }
            // A true side elevation makes the wheelbase, overhangs, beltline,
            // and mouse-to-car scale directly comparable in capture reviews.
            if car_orbit_view {
                angle := f32(car_orbit_degrees) * math.PI / 180
                editor.camera_pose = third_person.camera_look_at(
                    {math.sin(angle) * 4.8, 1.85, -math.cos(angle) * 4.8},
                    {0, .54, 0},
                )
            } else if showcase_view == "car-front" {
                editor.camera_pose = third_person.camera_look_at({0, 1.65, -4.6}, {0, .52, 0})
            } else if showcase_view == "car-rear" || showcase_view == "car-brake-rear" {
                editor.camera_pose = third_person.camera_look_at({0, 1.65, 4.6}, {0, .52, 0})
            } else {
                editor.camera_pose = third_person.camera_look_at({5.4, 2.0, 0}, {0, .56, 0})
            }
        }
        third_person.camera_set_pose(&editor.cameras, .Player, editor.camera_pose)
        third_person.camera_set_active(&editor.cameras, .Player)
        atmosphere.set_world_minutes(&editor.atmosphere, 16 * 60 + 45)
        atmosphere.set_weather_override(&editor.atmosphere, .Clear)
        editor.atmosphere.weather = atmosphere.weather_for(.Clear)
        editor.atmosphere.paused = true
        if capture_paint_mode {
            if target == "car" {
                fmt.eprintf("paint mode target must be postale, libellula, or libellula-mk2\n")
                return false
            }
            vehicle_paint_open(editor)
            if os.get_env("ADRIATIC_CAPTURE_PAINT_PANEL", context.temp_allocator) == "hidden" {
                editor.vehicle_paint_panel_visible = false
            }
        }
    }
    if capture_road_mode {
        editor.capture_world_only = true
        editor.editor_camera.distance = capture_road_dust_mode ? 165 : 210
        editor.editor_focus.x = island_center - 20
        editor.editor_focus.z = island_center - 5
        if capture_road_dust_mode && capture_target != "" {
            target_pavement := roads.Pavement.Asphalt
            switch capture_target {
            case "gravel":
                target_pavement = .Gravel
            case "cobble":
                target_pavement = .Cobblestone
            case "dirt":
                target_pavement = .Dirt
            }
            for edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
                if edge.pavement != target_pavement do continue
                point := roads.edge_point(&editor.project.road_graph, edge, .58)
                editor.editor_focus = {point.x, point.y + .5, point.z}
                editor.editor_camera.distance = 34
                editor.editor_camera.pitch_radians = .28
                break
            }
        }
        editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    }
    if capture_road_grip_mode {
        editor.capture_world_only = true
        editor.editor_focus = {editor.car.position.x, editor.car.position.y + .75, editor.car.position.z}
        editor.editor_camera = {
            yaw_radians   = math.PI * .72,
            pitch_radians = .48,
            distance      = 52,
        }
        editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    }
    if capture_terrain_grip_mode {
        editor.capture_world_only = true
        editor.editor_focus = {editor.car.position.x, editor.car.position.y + .75, editor.car.position.z}
        editor.editor_camera = {
            yaw_radians   = math.PI * .72,
            pitch_radians = .48,
            distance      = 48,
        }
        editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    }
    return true
}
