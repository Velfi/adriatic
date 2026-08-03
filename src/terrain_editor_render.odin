package main

import atmosphere "../packages/atmosphere"
import postale_game "../packages/postale"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

@(no_instrumentation)
terrain_color :: #force_inline proc(height, painted, sea_level, x, z: f32) -> canvas2d.Color {
    water := canvas2d.Color {
        r = 26,
        g = 80,
        b = 104,
        a = 255,
    }
    sand := canvas2d.Color {
        r = 205,
        g = 183,
        b = 126,
        a = 255,
    }
    soil := canvas2d.Color {
        r = 145,
        g = 101,
        b = 61,
        a = 255,
    }
    grass := canvas2d.Color {
        r = 70,
        g = 133,
        b = 80,
        a = 255,
    }
    if height <= sea_level do return water
    if painted < 0 {
        // Negative paint is a backward-compatible stabilized-sand mask used by
        // generated coastal dunes. -1 is active pale sand at any elevation;
        // values approaching zero reveal the ordinary elevation-driven cover.
        natural: canvas2d.Color
        elevation := height - sea_level
        if elevation < .9 {
            natural = color_lerp(sand, soil, clamp((elevation - .18) / .72, 0, 1))
        } else {
            natural = color_lerp(soil, grass, clamp((elevation - .9) / 3.1, 0, 1))
        }
        wetness := clamp(-painted - 1, 0, 1)
        stabilization := clamp(painted + 1, 0, 1)
        natural_recovery := stabilization * (.55 + stabilization * .45)
        base := color_lerp(sand, natural, natural_recovery)
        wet_sand := canvas2d.Color{151, 139, 103, 255}
        // Fine mottling is evaluated per fragment, but broad ecological
        // recovery stays in vertex colors so it meets ordinary terrain
        // continuously where the signed dune mask ends.
        return color_lerp(base, wet_sand, wetness * .72)
    }
    if painted > .5 do return terrain_color_variation(soil, x, z)

    elevation := height - sea_level
    // Broad blends keep the elevation bands from turning the heightfield cells
    // into hard material rings. The normal-based light applied by each renderer
    // then provides the small-scale shape and slope definition.
    if elevation < .9 {
        base := color_lerp(sand, soil, clamp((elevation - .18) / .72, 0, 1))
        return terrain_color_variation(base, x, z)
    }
    base := color_lerp(soil, grass, clamp((elevation - .9) / 3.1, 0, 1))
    return terrain_color_variation(base, x, z)
}

draw_line_3d :: proc(
    camera: Perspective_Camera,
    a, b: third_person.Vec3,
    width, height: i32,
    thickness: f32,
    color: canvas2d.Color,
) {
    pa := project_3d(camera, a, width, height)
    pb := project_3d(camera, b, width, height)
    if pa.visible && pb.visible do canvas2d.DrawLineEx(pa.position, pb.position, thickness, color)
}

draw_quad_3d :: proc(
    camera: Perspective_Camera,
    a, b, c, d: third_person.Vec3,
    width, height: i32,
    color: canvas2d.Color,
) {
    pa := project_3d(camera, a, width, height)
    pb := project_3d(camera, b, width, height)
    pc := project_3d(camera, c, width, height)
    pd := project_3d(camera, d, width, height)
    if pa.visible && pb.visible && pc.visible && pd.visible {
        canvas2d.DrawQuadHatched(pa.position, pb.position, pc.position, pd.position, color, canvas2d.HATCH_DISABLED)
    }
}

world_under_cursor_3d :: proc(
    camera: Perspective_Camera,
    mouse: canvas2d.Vector2,
    width, height: i32,
    plane_height: f32,
) -> (
    f32,
    f32,
    bool,
) {
    if width <= 0 || height <= 0 do return 0, 0, false
    screen_x := (mouse.x / f32(width) - .5) * 2
    screen_y := (.5 - mouse.y / f32(height)) * 2
    aspect := f32(width) / f32(height)
    direction := linalg.normalize0(
        third_person.Vec3 {
            camera.forward.x +
            camera.right.x * screen_x * aspect / camera.focal_length +
            camera.up.x * screen_y / camera.focal_length,
            camera.forward.y +
            camera.right.y * screen_x * aspect / camera.focal_length +
            camera.up.y * screen_y / camera.focal_length,
            camera.forward.z +
            camera.right.z * screen_x * aspect / camera.focal_length +
            camera.up.z * screen_y / camera.focal_length,
        },
    )
    if math.abs(direction.y) < .0001 do return 0, 0, false
    distance := (plane_height - camera.position.y) / direction.y
    if distance <= 0 do return 0, 0, false
    return camera.position.x + direction.x * distance, camera.position.z + direction.z * distance, true
}

editor_world_ray_direction :: proc(
    camera: Perspective_Camera,
    mouse: canvas2d.Vector2,
    width, height: i32,
) -> (
    third_person.Vec3,
    bool,
) {
    if width <= 0 || height <= 0 || camera.focal_length <= 0 do return {}, false
    screen_x := (mouse.x / f32(width) - .5) * 2
    screen_y := (.5 - mouse.y / f32(height)) * 2
    aspect := f32(width) / f32(height)
    direction := linalg.normalize0(
        third_person.Vec3 {
            camera.forward.x +
            camera.right.x * screen_x * aspect / camera.focal_length +
            camera.up.x * screen_y / camera.focal_length,
            camera.forward.y +
            camera.right.y * screen_x * aspect / camera.focal_length +
            camera.up.y * screen_y / camera.focal_length,
            camera.forward.z +
            camera.right.z * screen_x * aspect / camera.focal_length +
            camera.up.z * screen_y / camera.focal_length,
        },
    )
    return direction, linalg.dot(direction, direction) > 1e-8
}

terrain_under_cursor_3d :: proc(
    editor: ^Editor,
    camera: Perspective_Camera,
    mouse: canvas2d.Vector2,
    width, height: i32,
) -> (
    f32,
    f32,
    bool,
) {
    if editor == nil || width <= 0 || height <= 0 do return 0, 0, false
    direction, ray_ok := editor_world_ray_direction(camera, mouse, width, height)
    if !ray_ok do return 0, 0, false
    step := max(f32(terrain.BASE_CELL_SIZE * .5), f32(2))
    half := f32(terrain.WORLD_SIZE_METERS * .5)
    previous_distance := f32(.1)
    previous_delta := f32(1.0e30)
    for distance := step; distance <= terrain.WORLD_SIZE_METERS * 2; distance += step {
        x := camera.position.x + direction.x * distance
        y := camera.position.y + direction.y * distance
        z := camera.position.z + direction.z * distance
        if math.abs(x) > half || math.abs(z) > half {
            previous_distance = distance
            continue
        }
        delta := y - terrain.sample_surface_height(&editor.project, 0, x, z)
        if delta <= 0 && previous_delta > 0 {
            low, high := previous_distance, distance
            for _ in 0 ..< 10 {
                mid := (low + high) * .5
                mx := camera.position.x + direction.x * mid
                my := camera.position.y + direction.y * mid
                mz := camera.position.z + direction.z * mid
                if my > terrain.sample_surface_height(&editor.project, 0, mx, mz) {
                    low = mid
                } else {
                    high = mid
                }
            }
            hit_distance := (low + high) * .5
            return camera.position.x + direction.x * hit_distance, camera.position.z + direction.z * hit_distance, true
        }
        previous_distance = distance
        previous_delta = delta
    }
    return 0, 0, false
}

update_editor_camera :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    if editor_ui_hit(editor, canvas2d.GetMousePosition(), canvas2d.GetScreenWidth(), canvas2d.GetScreenHeight()) do return
    if canvas2d.IsMouseButtonDown(.MIDDLE) {
        mouse_delta := canvas2d.GetMouseDelta()
        third_person.look(&editor.editor_camera, -mouse_delta.x, mouse_delta.y, .006)
    }
    if !imgui_captures_keyboard() {
        rotate_direction := f32(0)
        if canvas2d.IsKeyDown(.Q) do rotate_direction -= 1
        if canvas2d.IsKeyDown(.E) do rotate_direction += 1
        editor.editor_camera.yaw_radians += rotate_direction * 1.5 * delta_seconds
    }
    wheel := canvas2d.GetMouseWheelMove()
    if wheel != 0 && !shift_key_down() && !alt_key_down() {
        editor.editor_camera.distance = clamp(
            editor.editor_camera.distance * f32(math.pow(0.82, f64(wheel))),
            80,
            5000,
        )
    }
    move_x, move_z := f32(0), f32(0)
    if canvas2d.IsKeyDown(.D) do move_x += 1
    if canvas2d.IsKeyDown(.A) do move_x -= 1
    if canvas2d.IsKeyDown(.W) do move_z += 1
    if canvas2d.IsKeyDown(.S) do move_z -= 1
    yaw := editor.editor_camera.yaw_radians
    forward := third_person.Vec3{-math.sin(yaw), 0, -math.cos(yaw)}
    right := third_person.Vec3{math.cos(yaw), 0, -math.sin(yaw)}
    speed := clamp(editor.editor_camera.distance * .8, 80, 1600)
    if shift_key_down() do speed *= 2
    editor.editor_focus.x += (forward.x * move_z + right.x * move_x) * speed * delta_seconds
    editor.editor_focus.z += (forward.z * move_z + right.z * move_x) * speed * delta_seconds
    half := f32(terrain.WORLD_SIZE_METERS * .5)
    editor.editor_focus.x = clamp(editor.editor_focus.x, -half, half)
    editor.editor_focus.z = clamp(editor.editor_focus.z, -half, half)
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    editor.cameras = third_person.camera_system(editor.camera_pose)
}

editor_focus_terrain :: proc(editor: ^Editor) {
    if editor == nil do return
    focus := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    editor.editor_focus = {focus, 0, focus}
    editor.editor_camera.distance = 900
    if editor.structure_selected >= 0 && editor.structure_selected < editor.project.structure_count {
        structure := editor.project.structures[editor.structure_selected]
        editor.editor_focus = {structure.center_x, structure.base_y + structure.height * .35, structure.center_z}
        editor.editor_camera.distance = clamp(max(structure.width, structure.depth) * 4.5, 180, 1800)
    }
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    editor.cameras = third_person.camera_system(editor.camera_pose)
}

draw_infrastructure_3d :: proc(editor: ^Editor, camera: Perspective_Camera, width, height: i32) {
    if editor.postale_visible do draw_postale_3d(editor, camera, width, height)
    // The spawned inspection craft is a world object; keep it in the
    // infrastructure pass even when the parked-vehicle presentation toggles.
    draw_libellula_3d(editor, camera, width, height)
}

draw_terrain_3d :: proc(editor: ^Editor, width, height: i32) {
    sky := atmosphere_sky(editor)
    horizon_day := canvas2d.Color {
        r = 154,
        g = 205,
        b = 224,
        a = 255,
    }
    horizon_night := canvas2d.Color {
        r = 19,
        g = 28,
        b = 55,
        a = 255,
    }
    sky_color := color_lerp(horizon_night, horizon_day, sky.daylight)
    storm_horizon := canvas2d.Color {
        r = 104,
        g = 122,
        b = 130,
        a = 255,
    }
    sky_color = color_lerp(sky_color, storm_horizon, sky.weather.severity * .72)
    // The fallback extends the ocean beyond the finite detail mesh. Match the
    // lit water presentation so the near-plane edge never becomes visible.
    ocean_color := canvas2d.Color {
        r = 86,
        g = 146,
        b = 165,
        a = 255,
    }
    canvas2d.ClearBackground(ocean_color)
    camera := perspective_camera(editor.camera_pose)
    // Build terrain in camera-space order: far rows first give the canvas pass
    // stable painter's depth while each face is still perspective-projected.
    forward_flat := linalg.normalize0(third_person.Vec3{camera.forward.x, 0, camera.forward.z})
    right_flat := linalg.normalize0(third_person.Vec3{camera.right.x, 0, camera.right.z})
    horizon := project_3d(
        camera,
        {
            camera.position.x + forward_flat.x * 10000,
            editor.project.sea_level,
            camera.position.z + forward_flat.z * 10000,
        },
        width,
        height,
    )
    if horizon.visible {
        horizon_y := i32(clamp(horizon.position.y, 0, f32(height)))
        canvas2d.DrawRectangle(0, 0, width, horizon_y + 1, sky_color)
    }
    // Match the finest clipmap spacing. Sampling every other heightfield point
    // made nearby slopes visibly faceted and discarded half of the authored
    // terrain detail.
    cell_size := editor.project.levels[0].cell_size
    // Keep the same world-space coverage as the former two-unit grid.
    near_rows := 48
    far_rows := 176
    side_rows := 180
    light_direction := linalg.normalize0(third_person.Vec3{-.45, .85, -.3})
    fog_start := f32(terrain.WORLD_SIZE_METERS * .55)
    fog_end := f32(terrain.WORLD_SIZE_METERS * 1.5)
    for depth_order in 0 ..< near_rows + far_rows {
        depth_index := near_rows + far_rows - 1 - depth_order
        depth := f32(depth_index - near_rows) * cell_size
        for side_index in -side_rows ..= side_rows {
            side := f32(side_index) * cell_size
            base_x := editor.camera_pose.target.x + forward_flat.x * depth + right_flat.x * side
            base_z := editor.camera_pose.target.z + forward_flat.z * depth + right_flat.z * side
            next_x := base_x + right_flat.x * cell_size
            next_z := base_z + right_flat.z * cell_size
            far_x := base_x + forward_flat.x * cell_size
            far_z := base_z + forward_flat.z * cell_size
            far_next_x := far_x + right_flat.x * cell_size
            far_next_z := far_z + right_flat.z * cell_size
            h00 := terrain.sample_surface_height(&editor.project, 0, base_x, base_z)
            h10 := terrain.sample_surface_height(&editor.project, 0, next_x, next_z)
            h01 := terrain.sample_surface_height(&editor.project, 0, far_x, far_z)
            h11 := terrain.sample_surface_height(&editor.project, 0, far_next_x, far_next_z)
            p00 := project_3d(camera, {base_x, h00, base_z}, width, height)
            p10 := project_3d(camera, {next_x, h10, next_z}, width, height)
            p11 := project_3d(camera, {far_next_x, h11, far_next_z}, width, height)
            p01 := project_3d(camera, {far_x, h01, far_z}, width, height)
            if !(p00.visible && p10.visible && p11.visible && p01.visible) do continue
            average_height := (h00 + h10 + h11 + h01) * .25
            surface_right := third_person.Vec3{next_x - base_x, h10 - h00, next_z - base_z}
            surface_forward := third_person.Vec3{far_x - base_x, h01 - h00, far_z - base_z}
            surface_normal := linalg.normalize0(linalg.cross(surface_right, surface_forward))
            diffuse := max(linalg.dot(surface_normal, light_direction), 0)
            shade := clamp(.52 + diffuse * .48 + average_height * .012, .42, 1.05)
            base_color := terrain_color(
                average_height,
                terrain.sample_material(&editor.project, 0, base_x, base_z),
                editor.project.sea_level,
                (base_x + far_next_x) * .5,
                (base_z + far_next_z) * .5,
            )
            color := canvas2d.Color {
                r = u8(f32(base_color.r) * shade),
                g = u8(f32(base_color.g) * shade),
                b = u8(f32(base_color.b) * shade),
                a = 255,
            }
            average_depth := (p00.depth + p10.depth + p11.depth + p01.depth) * .25
            fog := clamp((average_depth - fog_start) / (fog_end - fog_start), 0, 1)
            color = color_lerp(color, sky_color, fog)
            canvas2d.DrawQuadHatched(
                p00.position,
                p10.position,
                p11.position,
                p01.position,
                color,
                canvas2d.HATCH_DISABLED,
            )
        }
    }

    draw_infrastructure_3d(editor, camera, width, height)

    if editor.in_map && editor.pilot.mode == .On_Foot {
        // A compact articulated silhouette grounds the character in the 3D world.
        p := editor.player.position
        body := canvas2d.Color {
            r = 42,
            g = 213,
            b = 201,
            a = 255,
        }
        skin := canvas2d.Color {
            r = 247,
            g = 221,
            b = 167,
            a = 255,
        }
        draw_line_3d(camera, {p.x, p.y + .2, p.z}, {p.x, p.y + 1.35, p.z}, width, height, 7, body)
        draw_line_3d(camera, {p.x, p.y + 1.35, p.z}, {p.x, p.y + 1.62, p.z}, width, height, 12, skin)
        forward := third_person.Vec3 {
            -math.sin(editor.player.facing_yaw_radians),
            0,
            -math.cos(editor.player.facing_yaw_radians),
        }
        draw_line_3d(
            camera,
            {p.x, p.y + 1.12, p.z},
            {p.x + forward.x * .48, p.y + 1.12, p.z + forward.z * .48},
            width,
            height,
            4,
            skin,
        )

    }

    if editor.in_map && !editor.capture_world_only {
        flying := driving_aircraft(editor)
        in_car := driving_car(editor)
        driving := flying || in_car
        panel_width := driving ? i32(650) : i32(430)
        if flying && editor.aircraft.active != .Postale do panel_width = 800
        help_text: cstring = "WASD move  Mouse look  Wheel zoom  Space jump  Esc pause"
        if controller_prompt_active(editor) {
            panel_width = 790
            help_text = fmt.ctprintf(
                "LS move  RS look  LT/RT zoom  %s jump/drift  %s run  %s interact  Start pause",
                controller_face_label(editor, .South),
                controller_face_label(editor, .North),
                controller_face_label(editor, .West),
            )
        }
        if flying {
            help_text = "W/S pitch  A/D roll  Q/E yaw  Mouse orbit  C camera  Shift/Ctrl power  F exit  R reset"
            if controller_prompt_active(editor) {
                panel_width = 940
                help_text = fmt.ctprintf(
                    "LS fly  RS camera  LB/RB yaw  LT/RT power  %s recenter  %s exit  %s reset",
                    controller_face_label(editor, .South),
                    controller_face_label(editor, .West),
                    controller_face_label(editor, .North),
                )
            }
            if editor.aircraft.active != .Postale {
                help_text = "W/S pitch  A/D roll  Q/E yaw  Shift climb  Ctrl descend  Release to hover  F exit  R reset"
                if controller_prompt_active(editor) {
                    help_text = fmt.ctprintf(
                        "LS fly  RS camera  LB/RB yaw  LT/RT altitude  %s recenter  %s exit  %s reset",
                        controller_face_label(editor, .South),
                        controller_face_label(editor, .West),
                        controller_face_label(editor, .North),
                    )
                }
            }
        }
        if in_car {
            help_text = "W/S drive  A/D steer  Space handbrake  F exit  Esc pause"
            if controller_prompt_active(editor) {
                panel_width = 760
                help_text = fmt.ctprintf(
                    "LT/RT drive  LS steer  RS look  RB handbrake  %s exit  Start pause",
                    controller_face_label(editor, .West),
                )
            }
        }
        panel_width = min(panel_width, width - 28)
        canvas2d.DrawRectangle(14, 14, panel_width, 72, {r = 8, g = 28, b = 45, a = 210})
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            flying ? fmt.ctprintf("%s FLIGHT", vehicles.aircraft_kind_name(editor.aircraft.active)) : (in_car ? "DRIVING" : "ON FOOT"),
            {26, 25},
            19,
            1,
            {r = 211, g = 250, b = 242, a = 255},
        )
        canvas2d.DrawTextEx(canvas2d.Font{}, help_text, {26, 49}, 13, 1, {r = 183, g = 219, b = 221, a = 255})
        if flying {
            aircraft_body := active_aircraft_body(editor)
            ground := postale_game.drivable_surface_height(
                terrain.sample_surface_height(&editor.project, 0, aircraft_body.position.x, aircraft_body.position.z),
                editor.project.sea_level,
            )
            altitude := max(f32(0), aircraft_body.position.y - ground - active_aircraft_ground_clearance(editor))
            hud := fmt.tprintf(
                "THR %3.0f%%   AIR %3.0f m/s   ALT %3.0f m",
                active_aircraft_throttle(editor) * 100,
                active_aircraft_airspeed(editor),
                altitude,
            )
            canvas2d.DrawTextEx(
                canvas2d.Font{},
                fmt.ctprintf("%s", hud),
                {26, 68},
                13,
                1,
                {r = 236, g = 239, b = 190, a = 255},
            )
            draw_flight_instruments(editor, width, height, altitude)
            crashed := editor.aircraft.active != .Postale ? editor.libellula.crashed : editor.postale.crashed
            if editor.aircraft.active == .Postale &&
               editor.postale.landing_feedback_seconds > 0 &&
               editor.postale.last_landing.outcome != .None {
                landing := editor.postale.last_landing
                color := canvas2d.Color{92, 219, 213, 255}
                if landing.outcome == .Landed do color = {239, 203, 111, 255}
                if landing.outcome == .Hard_Landing do color = {255, 151, 83, 255}
                label := postale_game.landing_outcome_label(landing.outcome)
                detail := fmt.ctprintf(
                    "%.1f g   %.0f kN   DAMAGE %.0f%%",
                    landing.load_factor,
                    landing.impact_force / 1000,
                    editor.postale.structural_damage * 100,
                )
                label_size := canvas2d.MeasureTextEx(canvas2d.Font{}, label, 22, 1)
                detail_size := canvas2d.MeasureTextEx(canvas2d.Font{}, detail, 13, 1)
                canvas2d.DrawTextEx(canvas2d.Font{}, label, {f32(width) * .5 - label_size.x * .5, 28}, 22, 1, color)
                canvas2d.DrawTextEx(canvas2d.Font{}, detail, {f32(width) * .5 - detail_size.x * .5, 54}, 13, 1, color)
            }
            if crashed {
                canvas2d.DrawRectangle(width / 2 - 155, height / 2 - 35, 310, 70, {r = 71, g = 18, b = 20, a = 225})
                reset_key: cstring = controller_prompt_active(editor) ? controller_face_label(editor, .North) : "R"
                canvas2d.DrawTextEx(
                    canvas2d.Font{},
                    fmt.ctprintf(
                        "%s CRASHED — PRESS %s TO RESET",
                        vehicles.aircraft_kind_name(editor.aircraft.active),
                        reset_key,
                    ),
                    {f32(width / 2 - 139), f32(height / 2 - 8)},
                    16,
                    1,
                    {r = 255, g = 221, b = 195, a = 255},
                )
            } else if editor.aircraft.active == .Postale && editor.postale.telemetry.is_stalling {
                canvas2d.DrawTextEx(
                    canvas2d.Font{},
                    "STALL",
                    {f32(width / 2 - 28), 28},
                    22,
                    1,
                    {r = 255, g = 110, b = 83, a = 255},
                )
            }
        } else {
            delta := (editor.player.position - editor.postale.vehicle.position)
            if linalg.dot(delta, delta) <=
               editor.postale.vehicle.interaction_radius * editor.postale.vehicle.interaction_radius {
                canvas2d.DrawRectangle(width / 2 - 116, height - 92, 232, 42, {r = 8, g = 28, b = 45, a = 220})
                entry_prompt: cstring = "PRESS F TO ENTER POSTALE"
                if controller_prompt_active(editor) {
                    entry_prompt = fmt.ctprintf("PRESS %s TO ENTER POSTALE", controller_face_label(editor, .West))
                }
                canvas2d.DrawTextEx(
                    canvas2d.Font{},
                    entry_prompt,
                    {f32(width / 2 - 99), f32(height - 77)},
                    15,
                    1,
                    {r = 245, g = 239, b = 192, a = 255},
                )
            }
        }
    } else {
        if editor.selection_tool_active && editor.island_selected != .World {
            island_x, island_z, island_ok := terrain.island_center(&editor.project, editor.island_selected)
            if island_ok {
                island_y := terrain.sample_surface_height(&editor.project, 0, island_x, island_z) + 8
                center := project_3d(camera, {island_x, island_y, island_z}, width, height)
                axis_x := project_3d(camera, {island_x + 140, island_y, island_z}, width, height)
                axis_z := project_3d(camera, {island_x, island_y, island_z + 140}, width, height)
                if center.visible && axis_x.visible {
                    canvas2d.DrawLineEx(center.position, axis_x.position, 4, {208, 92, 82, 255})
                }
                if center.visible && axis_z.visible {
                    canvas2d.DrawLineEx(center.position, axis_z.position, 4, {69, 173, 163, 255})
                }
                if center.visible do canvas2d.DrawCircleV(center.position, 8, {235, 239, 243, 255})
            }
        }
        world_x, world_z, hit := world_under_cursor_3d(
            camera,
            canvas2d.GetMousePosition(),
            width,
            height,
            terrain.DEFAULT_ISLAND_HEIGHT,
        )
        if hit {
            brush_height := terrain.sample_surface_height(&editor.project, 0, world_x, world_z) + .08
            brush_center := project_3d(camera, {world_x, brush_height, world_z}, width, height)
            brush_edge := project_3d(camera, {world_x + editor.radius, brush_height, world_z}, width, height)
            if brush_center.visible && brush_edge.visible {
                brush_radius := f32(
                    math.sqrt(
                        f64(
                            (brush_edge.position.x - brush_center.position.x) *
                                (brush_edge.position.x - brush_center.position.x) +
                            (brush_edge.position.y - brush_center.position.y) *
                                (brush_edge.position.y - brush_center.position.y),
                        ),
                    ),
                )
                canvas2d.DrawCircleV(brush_center.position, brush_radius, {r = 230, g = 244, b = 218, a = 55})
            }
        }
        canvas2d.DrawRectangle(14, 14, 520, 42, {r = 8, g = 28, b = 45, a = 210})
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            "WASD pan  Q/E rotate  Middle orbit  Wheel zoom  Shift+wheel strength  Left/Right brush",
            {26, 29},
            12,
            1,
            {r = 183, g = 219, b = 221, a = 255},
        )
        draw_spawn_button()
    }
    minutes := int(sky.world_minutes)
    weather_label := atmosphere.preset_name(editor.atmosphere.override)
    clock := fmt.tprintf(
        "%02d:%02d  %s%s  [P] pause  [←/→] time  [4] auto  [1/2/3] weather",
        minutes / 60,
        minutes % 60,
        weather_label,
        editor.atmosphere.paused ? " PAUSED" : "",
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf("%s", clock),
        {f32(width) - 545, 18},
        13,
        1,
        {r = 224, g = 239, b = 231, a = 240},
    )
}

draw_infinite_ocean :: proc(width, height: i32, time: f32) {
    canvas2d.ClearBackground({r = 14, g = 54, b = 79, a = 255})
    for row in 0 ..< 24 {
        y := f32(row) * f32(height) / 23
        phase := f32(math.sin(f64(time * .9 + f32(row) * .73)))
        canvas2d.DrawLineEx({0, y}, {f32(width), y + phase * 3}, 1, {r = 35, g = 102, b = 128, a = 110})
    }
}

editor_palette_bounds :: proc() -> canvas2d.Rectangle {
    return {x = 20, y = 116, width = 830, height = 38}
}
