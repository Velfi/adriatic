package main

import atmosphere "../packages/atmosphere"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

MOUSE_WHEEL_RADIUS :: f32(4.2)
MOUSE_WHEEL_MOUSE_RADIUS :: f32(2.8)
MOUSE_WHEEL_PRESS_DISTANCE :: f32(.42)
MOUSE_WHEEL_INERTIA :: f32(8.5)
MOUSE_WHEEL_MOUSE_MASS :: f32(.34)
MOUSE_WHEEL_MAX_TRACTION :: f32(2.4)
MOUSE_WHEEL_AXLE_RESISTANCE :: f32(.055)

mouse_wheel_step: int
mouse_wheel_runner_speed: f32
mouse_wheel_mouse_speed: f32
mouse_wheel_angular_velocity: f32
mouse_wheel_peak_speed: f32
mouse_wheel_angle: f32
mouse_wheel_mouse_angle: f32
mouse_wheel_stride_phase: f32
mouse_wheel_jolt: f32
mouse_wheel_jolt_velocity: f32
mouse_wheel_slip: f32
mouse_wheel_last_press_time: f32
mouse_wheel_last_update_time: f32
mouse_wheel_mistake_flash_until: f32
mouse_wheel_press_count: int
town_mouse_wheel_mounted: bool
town_mouse_wheel_dismount_hold: f32

mouse_wheel_lab_reset :: proc(editor: ^Editor) {
    mouse_wheel_step = 0
    mouse_wheel_runner_speed = 0
    mouse_wheel_mouse_speed = 0
    mouse_wheel_angular_velocity = 0
    mouse_wheel_peak_speed = 0
    mouse_wheel_angle = 0
    mouse_wheel_mouse_angle = -math.PI * .5
    mouse_wheel_stride_phase = 0
    mouse_wheel_jolt = 0
    mouse_wheel_jolt_velocity = 0
    mouse_wheel_slip = 0
    mouse_wheel_last_press_time = 0
    mouse_wheel_mistake_flash_until = 0
    mouse_wheel_press_count = 0
    mouse_wheel_last_update_time = editor != nil ? editor.map_time : 0
    town_mouse_wheel_mounted = false
    town_mouse_wheel_dismount_hold = 0
}

mouse_wheel_lab_configure :: proc(editor: ^Editor, _: string) -> bool {
    if editor == nil do return false
    mouse_wheel_lab_reset(editor)
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 10)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    set_pointer_locked(false)
    editor.camera_pose = third_person.camera_look_at({11.5, 10.5, 13.5}, {0, 1.2, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

mouse_wheel_lab_press :: proc(editor: ^Editor, pressed_step: int) {
    if editor == nil do return
    now := editor.map_time
    if pressed_step != mouse_wheel_step {
        mouse_wheel_step = 0
        mouse_wheel_mistake_flash_until = now + .35
        return
    }

    if mouse_wheel_last_press_time > 0 {
        interval := clamp(f32(now - mouse_wheel_last_press_time), .055, .8)
        instant_speed := MOUSE_WHEEL_PRESS_DISTANCE / interval
        mouse_wheel_runner_speed =
            mouse_wheel_press_count < 2 ? instant_speed : mouse_wheel_runner_speed * .58 + instant_speed * .42
        mouse_wheel_peak_speed = max(mouse_wheel_peak_speed, mouse_wheel_runner_speed)
    }
    mouse_wheel_last_press_time = now
    mouse_wheel_press_count += 1
    mouse_wheel_step = (mouse_wheel_step + 1) % 4

    // A paw plant is an internal impulse: the mouse goes forward and the wheel
    // receives exactly the opposite angular momentum.
    impulse := f32(.075)
    mouse_wheel_mouse_speed += impulse / MOUSE_WHEEL_MOUSE_MASS
    mouse_wheel_angular_velocity -= impulse * MOUSE_WHEEL_MOUSE_RADIUS / MOUSE_WHEEL_INERTIA
    mouse_wheel_jolt_velocity += .42 + min(mouse_wheel_runner_speed, 4) * .08
}

mouse_wheel_lab_process_input :: proc(editor: ^Editor) {
    if canvas2d.IsKeyPressed(.ONE) do mouse_wheel_lab_press(editor, 0)
    if canvas2d.IsKeyPressed(.TWO) do mouse_wheel_lab_press(editor, 1)
    if canvas2d.IsKeyPressed(.THREE) do mouse_wheel_lab_press(editor, 2)
    if canvas2d.IsKeyPressed(.FOUR) do mouse_wheel_lab_press(editor, 3)
    if canvas2d.IsKeyPressed(.R) do mouse_wheel_lab_reset(editor)
}

town_mouse_wheel_center :: proc(editor: ^Editor) -> (position: third_person.Vec3, rotation: f32, found: bool) {
    if editor == nil do return
    plan := editor_circulation_plan(editor)
    if plan == nil do return
    best_index := -1
    best_area := f32(0)
    for area, area_index in plan.areas[:plan.count] {
        if area.kind != .Plaza do continue
        area_size := area.width * area.length
        if area_size > best_area {
            best_area = area_size
            best_index = area_index
        }
    }
    if best_index < 0 do return
    area := plan.areas[best_index]
    x, z := world_town_mouse_wheel_position(area)
    y := terrain.sample_surface_height(&editor.project, 0, x, z)
    return {x, y, z}, area.rotation, true
}

town_mouse_wheel_near :: proc(editor: ^Editor) -> bool {
    center, _, found := town_mouse_wheel_center(editor)
    if !found do return false
    dx := editor.player.position.x - center.x
    dz := editor.player.position.z - center.z
    return dx * dx + dz * dz <= 2.45 * 2.45
}

town_mouse_wheel_apply_player :: proc(editor: ^Editor, center: third_person.Vec3) {
    radius := f32(1.02)
    x := center.x + math.cos(mouse_wheel_mouse_angle) * radius
    z := center.z + math.sin(mouse_wheel_mouse_angle) * radius
    y := center.y + .29 + mouse_wheel_jolt
    facing := mouse_wheel_mouse_angle + math.PI * .5
    tangent_x, tangent_z := -math.sin(mouse_wheel_mouse_angle), math.cos(mouse_wheel_mouse_angle)
    editor.player.position = {x, y, z}
    editor.player.velocity = {tangent_x * mouse_wheel_mouse_speed, 0, tangent_z * mouse_wheel_mouse_speed}
    editor.player.facing_yaw_radians = facing
    editor.player.grounded = true
    editor.pilot.position = editor.player.position
    editor.pilot.facing_yaw_radians = facing
    gameplay_physics_teleport_player(editor)
}

town_mouse_wheel_run_input :: proc(editor: ^Editor) {
    if canvas2d.IsKeyPressed(.ONE) || gamepad_pressed(.South) do mouse_wheel_lab_press(editor, 0)
    if canvas2d.IsKeyPressed(.TWO) || gamepad_pressed(.East) do mouse_wheel_lab_press(editor, 1)
    if canvas2d.IsKeyPressed(.THREE) || gamepad_pressed(.North) do mouse_wheel_lab_press(editor, 2)
    if canvas2d.IsKeyPressed(.FOUR) || gamepad_pressed(.West) do mouse_wheel_lab_press(editor, 3)
}

town_mouse_wheel_dismount :: proc(editor: ^Editor, center: third_person.Vec3) {
    town_mouse_wheel_mounted = false
    town_mouse_wheel_dismount_hold = 0
    exit_radius := f32(2.05)
    exit_x := center.x + math.cos(mouse_wheel_mouse_angle) * exit_radius
    exit_z := center.z + math.sin(mouse_wheel_mouse_angle) * exit_radius
    exit_y := terrain.sample_surface_height(&editor.project, 0, exit_x, exit_z)
    player_place(editor, {exit_x, exit_y, exit_z}, .Teleport, mouse_wheel_mouse_angle + math.PI * .5)
}

// Returns true when this frame's F press was consumed by mounting or
// dismounting, so another nearby gameplay interaction cannot also fire.
town_mouse_wheel_gameplay_process :: proc(editor: ^Editor, delta_seconds: f32) -> bool {
    if editor == nil || editor.active_lab_scene != "" do return false
    center, _, found := town_mouse_wheel_center(editor)
    if !found {
        town_mouse_wheel_mounted = false
        return false
    }

    if town_mouse_wheel_mounted {
        if canvas2d.IsKeyPressed(.F) {
            town_mouse_wheel_dismount(editor, center)
            return true
        }
        town_mouse_wheel_run_input(editor)
        if gamepad_down(.West) {
            town_mouse_wheel_dismount_hold += delta_seconds
            if town_mouse_wheel_dismount_hold >= .65 {
                town_mouse_wheel_dismount(editor, center)
                return true
            }
        } else {
            town_mouse_wheel_dismount_hold = 0
        }
        mouse_wheel_lab_update(editor)
        town_mouse_wheel_apply_player(editor, center)
        return false
    }

    // An unoccupied wheel keeps coasting and losing energy.
    mouse_wheel_lab_update(editor)
    if input_action_pressed(.Interact) && town_mouse_wheel_near(editor) {
        mouse_wheel_lab_reset(editor)
        dx := editor.player.position.x - center.x
        dz := editor.player.position.z - center.z
        mouse_wheel_mouse_angle = math.atan2(dz, dx)
        town_mouse_wheel_mounted = true
        town_mouse_wheel_dismount_hold = 0
        town_mouse_wheel_apply_player(editor, center)
        return true
    }
    _ = delta_seconds
    return false
}

mouse_wheel_lab_update :: proc(editor: ^Editor) {
    now := editor.map_time
    dt := clamp(f32(now - mouse_wheel_last_update_time), 0, .1)
    mouse_wheel_last_update_time = now
    idle_seconds := mouse_wheel_last_press_time > 0 ? f32(now - mouse_wheel_last_press_time) : f32(10)
    if idle_seconds > .18 {
        mouse_wheel_runner_speed = max(0, mouse_wheel_runner_speed - dt * (1.6 + mouse_wheel_runner_speed * .9))
    }

    // Integrate the coupled bodies in small steps. Paw traction attempts to
    // produce the commanded velocity relative to the deck. When the command
    // vanishes, the same contact becomes passive friction and the still-moving
    // wheel is free to carry the mouse with it.
    SUBSTEPS :: 4
    step_dt := dt / SUBSTEPS
    for _ in 0 ..< SUBSTEPS {
        deck_speed_at_mouse := mouse_wheel_angular_velocity * MOUSE_WHEEL_MOUSE_RADIUS
        contact_relative_speed := mouse_wheel_mouse_speed - deck_speed_at_mouse
        traction_error := mouse_wheel_runner_speed - contact_relative_speed
        traction_force := clamp(traction_error * 4.8, -MOUSE_WHEEL_MAX_TRACTION, MOUSE_WHEEL_MAX_TRACTION)

        mouse_wheel_mouse_speed += traction_force / MOUSE_WHEEL_MOUSE_MASS * step_dt
        mouse_wheel_angular_velocity -= traction_force * MOUSE_WHEEL_MOUSE_RADIUS / MOUSE_WHEEL_INERTIA * step_dt

        // Axle torque, aerodynamic wheel drag, and the mouse's foot/body drag
        // are external losses, so total angular momentum decays naturally.
        wheel_drag_torque :=
            MOUSE_WHEEL_AXLE_RESISTANCE * mouse_wheel_angular_velocity +
            mouse_wheel_angular_velocity * abs(mouse_wheel_angular_velocity) * .035
        mouse_wheel_angular_velocity -= wheel_drag_torque / MOUSE_WHEEL_INERTIA * step_dt
        mouse_wheel_mouse_speed -= mouse_wheel_mouse_speed * .18 * step_dt
    }
    deck_speed_at_mouse := mouse_wheel_angular_velocity * MOUSE_WHEEL_MOUSE_RADIUS
    mouse_wheel_slip = mouse_wheel_mouse_speed - deck_speed_at_mouse

    // The compliant axle mount turns each footfall into a visible, damped jolt.
    mouse_wheel_jolt_velocity += (-mouse_wheel_jolt * 34 - mouse_wheel_jolt_velocity * 8.5) * dt
    mouse_wheel_jolt += mouse_wheel_jolt_velocity * dt

    mouse_wheel_mouse_angle += mouse_wheel_mouse_speed / MOUSE_WHEEL_MOUSE_RADIUS * dt
    mouse_wheel_angle += mouse_wheel_angular_velocity * dt
    mouse_wheel_stride_phase +=
        mouse_wheel_runner_speed * mouse_gait_lab_stride_rate(editor, max(mouse_wheel_runner_speed, .01)) * dt
}

world_mouse_wheel_lab :: proc(editor: ^Editor) {
    if editor == nil do return
    mouse_wheel_lab_update(editor)

    // A low, saucer-style exercise wheel: its broad running deck spins in the
    // horizontal plane while the mouse holds a fixed inspection position.
    world_box({0, -.22, 0}, {13, .32, 13}, {205, 195, 170, 255})
    world_vertical_prism({0, .04, 0}, MOUSE_WHEEL_RADIUS + .22, MOUSE_WHEEL_RADIUS + .22, .22, 0, {70, 79, 86, 255})
    deck_height := .18 + mouse_wheel_jolt
    world_vertical_prism({0, deck_height, 0}, MOUSE_WHEEL_RADIUS, MOUSE_WHEEL_RADIUS, .12, 0, {125, 151, 153, 255})
    world_vertical_prism({0, deck_height + .09, 0}, .42, .42, .18, 0, {210, 171, 92, 255})

    for marker in 0 ..< 16 {
        angle := mouse_wheel_angle + f32(marker) * math.PI * 2 / 16
        radius := MOUSE_WHEEL_RADIUS * .72
        x := math.cos(angle) * radius
        z := math.sin(angle) * radius
        marker_color := marker % 4 == 0 ? canvas2d.Color{236, 189, 91, 255} : canvas2d.Color{84, 105, 109, 255}
        world_box_rotated({x, deck_height + .075, z}, {.10, .025, 1.12}, angle + math.PI * .5, marker_color)
    }

    mouse_x := math.cos(mouse_wheel_mouse_angle) * MOUSE_WHEEL_MOUSE_RADIUS
    mouse_z := math.sin(mouse_wheel_mouse_angle) * MOUSE_WHEEL_MOUSE_RADIUS
    world_mouse_model(
        editor,
        {
            position = {mouse_x, deck_height + .13, mouse_z},
            rotation = mouse_wheel_mouse_angle + math.PI * .5,
            fur = .Chestnut,
            pattern = .Solid,
            grounded = true,
            gait_preview = true,
            gait_speed = mouse_wheel_runner_speed,
            gait_phase = mouse_wheel_stride_phase,
        },
    )

    // Axle housing and four feet keep the wheel visually grounded as a lab rig.
    world_vertical_prism({0, -.02, 0}, .62, .62, .55, 0, {73, 70, 64, 255})
    for offset in ([4][2]f32{{-4.8, -4.8}, {4.8, -4.8}, {-4.8, 4.8}, {4.8, 4.8}}) {
        world_vertical_prism({offset[0], -.03, offset[1]}, .34, .34, .25, math.PI / 8, {83, 77, 66, 255})
    }
}

mouse_wheel_lab_draw_ui :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil do return
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 455,
        height = 184,
    }
    canvas2d.DrawRectangleRounded(panel, .08, 8, {13, 25, 30, 235})
    border :=
        editor.map_time < mouse_wheel_mistake_flash_until ? canvas2d.Color{225, 91, 76, 255} : canvas2d.Color{111, 181, 184, 255}
    canvas2d.DrawRectangleRoundedLinesEx(panel, .08, 8, 1, border)
    canvas2d.DrawTextEx(canvas2d.Font{}, "MOUSE WHEEL LAB", {38, 37}, 21, 1, {246, 236, 191, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "PRESS IN ORDER TO RUN   /   R RESET", {38, 68}, 13, 1, {193, 217, 218, 255})

    for index in 0 ..< 4 {
        x := 38 + f32(index) * 48
        active := index == mouse_wheel_step
        color := active ? canvas2d.Color{237, 187, 79, 255} : canvas2d.Color{63, 84, 89, 255}
        canvas2d.DrawRectangleRounded({x, 91, 36, 30}, .2, 5, color)
        label := fmt.ctprintf("%d", index + 1)
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            label,
            {x + 13, 97},
            16,
            1,
            active ? canvas2d.Color{27, 31, 30, 255} : canvas2d.Color{205, 219, 218, 255},
        )
    }

    wheel_speed_at_mouse := mouse_wheel_angular_velocity * MOUSE_WHEEL_MOUSE_RADIUS
    speed_color := abs(mouse_wheel_mouse_speed) > .05 ? canvas2d.Color{143, 224, 164, 255} : canvas2d.Color{171, 185, 184, 255}
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf(
            "MOUSE %+.2f m/s   DECK %+.2f m/s   PEAK %.2f",
            mouse_wheel_mouse_speed,
            wheel_speed_at_mouse,
            mouse_wheel_peak_speed,
        ),
        {38, 140},
        16,
        1,
        speed_color,
    )
    slip_color := abs(mouse_wheel_slip) > 1 ? canvas2d.Color{235, 151, 86, 255} : canvas2d.Color{169, 207, 193, 255}
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf(
            "SLIP %+.2f m/s   RESIST %.2f   JOLT %.2f",
            mouse_wheel_slip,
            MOUSE_WHEEL_AXLE_RESISTANCE,
            abs(mouse_wheel_jolt),
        ),
        {38, 164},
        13,
        1,
        slip_color,
    )
    _ = width
    _ = height
}

// Compact town wheels reuse the lab's saucer construction without sharing its
// global simulation state. They are civic exercise fixtures, placed beside the
// primary plaza by the settlement renderer.
world_town_mouse_wheel :: proc(center_x, base_y, center_z, rotation, wheel_angle, jolt: f32) {
    radius := f32(1.55)
    deck_y := base_y + .16 + jolt
    world_vertical_prism({center_x, base_y + .03, center_z}, radius + .13, radius + .13, .18, 0, {67, 75, 80, 255})
    world_vertical_prism({center_x, deck_y, center_z}, radius, radius, .10, 0, {121, 151, 151, 255})
    world_vertical_prism({center_x, deck_y + .08, center_z}, .22, .22, .16, 0, {211, 169, 83, 255})

    for notch in 0 ..< 12 {
        angle := rotation + wheel_angle + f32(notch) * math.PI * 2 / 12
        x := center_x + math.cos(angle) * radius * .70
        z := center_z + math.sin(angle) * radius * .70
        color := notch % 3 == 0 ? canvas2d.Color{231, 185, 91, 255} : canvas2d.Color{79, 100, 103, 255}
        world_box_rotated({x, deck_y + .06, z}, {.055, .022, .48}, angle + math.PI * .5, color)
    }

    for offset in ([4][2]f32{{-1.25, -1.25}, {1.25, -1.25}, {-1.25, 1.25}, {1.25, 1.25}}) {
        foot_x, foot_z := world_rotate_xz(center_x, center_z, offset[0], offset[1], rotation)
        world_vertical_prism({foot_x, base_y + .015, foot_z}, .16, .16, .16, math.PI / 8, {78, 72, 62, 255})
    }
}
