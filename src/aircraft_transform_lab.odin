package main

import chase_camera "../packages/chase_camera"
import flight "../packages/flight"
import third_person "zelda_engine:third_person"
import "core:math"
import "core:math/linalg"

aircraft_transform_lab_configure :: proc(editor: ^Editor, _: string) -> bool {
    if editor == nil do return false
    editor.capture_postale_bank_grid = false
    editor.capture_postale_transform_parity = true
    editor.aircraft.active = .Postale
    editor.postale_visible = true
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.in_map = true
    editor.postale.body.position = {0, 70, 0}
    pitch := linalg.quaternion_angle_axis(f32(10) * math.PI / 180, third_person.Vec3{1, 0, 0})
    roll := linalg.quaternion_angle_axis(f32(30) * math.PI / 180, third_person.Vec3{0, 0, 1})
    editor.postale.body.orientation = flight.normalize_orientation(roll * pitch * flight.identity_orientation())
    editor.postale.body.velocity = {0, 0, 0}
    editor.postale.grounded = false
    editor.postale.was_grounded = false
    editor.editor_focus = {0, 70, 0}
    chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
    editor.camera_pose = editor.flight_camera.pose
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

aircraft_transform_lab_world :: proc(_: ^Editor) {  }
aircraft_transform_lab_input :: proc(_: ^Editor) {  }
aircraft_transform_lab_ui :: proc(_: ^Editor, _: i32, _: i32) {  }
aircraft_transform_lab_exit :: proc(editor: ^Editor) {
    if editor != nil {
        editor.capture_postale_bank_grid = false
        editor.capture_postale_transform_parity = false
    }
}
