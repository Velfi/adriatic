package main

import flight "../packages/flight"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

SDF_TORUS_MAJOR_SEGMENTS :: 16
SDF_TORUS_TUBE_SEGMENTS :: 8
SDF_OBSTACLE_LIST_VISIBLE_COUNT :: 5
SDF_OBSTACLE_RAY_HIT_EPSILON :: f32(.025)
SDF_OBSTACLE_RAY_MAX_STEPS :: 192

SDF_OBSTACLE_DEFAULT_MAJOR_RADIUS :: f32(3)
SDF_OBSTACLE_DEFAULT_TUBE_RADIUS :: f32(.75)
SDF_OBSTACLE_MINIMUM_SCALE :: f32(.05)
SDF_OBSTACLE_MAXIMUM_SCALE :: f32(32)
SDF_OBSTACLE_MINIMUM_RADIUS :: f32(.05)
SDF_OBSTACLE_MAXIMUM_RADIUS :: f32(64)
SDF_OBSTACLE_POSITION_LIMIT :: f32(terrain.WORLD_SIZE_METERS * .5)
SDF_OBSTACLE_EULER_LIMIT_DEGREES :: f32(180)

SDF_OBSTACLE_DEFAULT_COLORS := [6][4]u8 {
    {224, 94, 76, 255},
    {81, 177, 224, 255},
    {229, 178, 69, 255},
    {131, 203, 116, 255},
    {190, 126, 221, 255},
    {226, 145, 90, 255},
}

sdf_obstacle_active_count :: #force_inline proc(editor: ^Editor) -> int {
    if editor == nil || editor.sdf_obstacle_count < 0 || editor.sdf_obstacle_count > len(editor.sdf_obstacles) {
        return 0
    }
    return editor.sdf_obstacle_count
}

sdf_obstacle_selected_ptr :: #force_inline proc(editor: ^Editor) -> ^SDF_Torus_Obstacle {
    count := sdf_obstacle_active_count(editor)
    if editor == nil || editor.sdf_obstacle_selected < 0 || editor.sdf_obstacle_selected >= count do return nil
    return &editor.sdf_obstacles[editor.sdf_obstacle_selected]
}

sdf_obstacle_inspector_euler_refresh :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    obstacle := sdf_obstacle_selected_ptr(editor)
    if obstacle == nil || !fixture_editor_orientation_valid(obstacle.rotation) {
        editor.sdf_obstacle_interaction.inspector_euler_valid = false
        return false
    }
    x, y, z := linalg.euler_angles_from_quaternion(flight.normalize_orientation(obstacle.rotation), .XYZ)
    degrees := flight.Vec3{x, y, z} * (180 / f32(math.PI))
    if !fixture_editor_vec3_finite(degrees) {
        editor.sdf_obstacle_interaction.inspector_euler_valid = false
        return false
    }
    editor.sdf_obstacle_interaction.inspector_euler = degrees
    editor.sdf_obstacle_interaction.inspector_euler_valid = true
    return true
}

sdf_obstacle_set_position :: proc(editor: ^Editor, position: flight.Vec3) -> bool {
    obstacle := sdf_obstacle_selected_ptr(editor)
    if obstacle == nil || !fixture_editor_vec3_finite(position) do return false
    obstacle.position = {
        clamp(position.x, -SDF_OBSTACLE_POSITION_LIMIT, SDF_OBSTACLE_POSITION_LIMIT),
        clamp(position.y, -SDF_OBSTACLE_POSITION_LIMIT, SDF_OBSTACLE_POSITION_LIMIT),
        clamp(position.z, -SDF_OBSTACLE_POSITION_LIMIT, SDF_OBSTACLE_POSITION_LIMIT),
    }
    return true
}

sdf_obstacle_set_scale :: proc(editor: ^Editor, scale: flight.Vec3) -> bool {
    obstacle := sdf_obstacle_selected_ptr(editor)
    if obstacle == nil || !fixture_editor_vec3_finite(scale) do return false
    obstacle.scale = {
        clamp(scale.x, SDF_OBSTACLE_MINIMUM_SCALE, SDF_OBSTACLE_MAXIMUM_SCALE),
        clamp(scale.y, SDF_OBSTACLE_MINIMUM_SCALE, SDF_OBSTACLE_MAXIMUM_SCALE),
        clamp(scale.z, SDF_OBSTACLE_MINIMUM_SCALE, SDF_OBSTACLE_MAXIMUM_SCALE),
    }
    return true
}

sdf_obstacle_set_major_radius :: proc(editor: ^Editor, radius: f32) -> bool {
    obstacle := sdf_obstacle_selected_ptr(editor)
    if obstacle == nil || !fixture_editor_scalar_finite(radius) do return false
    obstacle.major_radius = clamp(radius, SDF_OBSTACLE_MINIMUM_RADIUS, SDF_OBSTACLE_MAXIMUM_RADIUS)
    return true
}

sdf_obstacle_set_tube_radius :: proc(editor: ^Editor, radius: f32) -> bool {
    obstacle := sdf_obstacle_selected_ptr(editor)
    if obstacle == nil || !fixture_editor_scalar_finite(radius) do return false
    obstacle.tube_radius = clamp(radius, SDF_OBSTACLE_MINIMUM_RADIUS, SDF_OBSTACLE_MAXIMUM_RADIUS)
    return true
}

sdf_obstacle_set_color_rgb :: proc(editor: ^Editor, color: [3]u8) -> bool {
    obstacle := sdf_obstacle_selected_ptr(editor)
    if obstacle == nil do return false
    obstacle.color = {color[0], color[1], color[2], 255}
    return true
}

sdf_obstacle_set_rotation_euler_degrees :: proc(editor: ^Editor, degrees: flight.Vec3) -> bool {
    obstacle := sdf_obstacle_selected_ptr(editor)
    if obstacle == nil || !fixture_editor_vec3_finite(degrees) do return false
    bounded := flight.Vec3 {
        clamp(degrees.x, -SDF_OBSTACLE_EULER_LIMIT_DEGREES, SDF_OBSTACLE_EULER_LIMIT_DEGREES),
        clamp(degrees.y, -SDF_OBSTACLE_EULER_LIMIT_DEGREES, SDF_OBSTACLE_EULER_LIMIT_DEGREES),
        clamp(degrees.z, -SDF_OBSTACLE_EULER_LIMIT_DEGREES, SDF_OBSTACLE_EULER_LIMIT_DEGREES),
    }
    radians := bounded * (f32(math.PI) / 180)
    rotation := linalg.quaternion_from_euler_angles(radians.x, radians.y, radians.z, .XYZ)
    if !fixture_editor_orientation_valid(rotation) do return false
    obstacle.rotation = flight.normalize_orientation(rotation)
    editor.sdf_obstacle_interaction.inspector_euler = bounded
    editor.sdf_obstacle_interaction.inspector_euler_valid = true
    return true
}

sdf_obstacle_default :: proc(position: flight.Vec3, color_index: int) -> SDF_Torus_Obstacle {
    index := color_index % len(SDF_OBSTACLE_DEFAULT_COLORS)
    if index < 0 do index += len(SDF_OBSTACLE_DEFAULT_COLORS)
    return {
        position = position,
        rotation = flight.identity_orientation(),
        scale = {1, 1, 1},
        major_radius = SDF_OBSTACLE_DEFAULT_MAJOR_RADIUS,
        tube_radius = SDF_OBSTACLE_DEFAULT_TUBE_RADIUS,
        color = SDF_OBSTACLE_DEFAULT_COLORS[index],
    }
}

sdf_obstacle_select :: proc(editor: ^Editor, index: int) -> bool {
    count := sdf_obstacle_active_count(editor)
    if editor == nil || index < 0 || index >= count do return false
    editor.sdf_obstacle_selected = index
    _ = sdf_obstacle_inspector_euler_refresh(editor)
    sdf_obstacle_list_reveal_selected(editor)
    return true
}

sdf_obstacle_list_scroll_max :: #force_inline proc(editor: ^Editor) -> int {
    return max(sdf_obstacle_active_count(editor) - SDF_OBSTACLE_LIST_VISIBLE_COUNT, 0)
}

sdf_obstacle_list_scroll_clamp :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.sdf_obstacle_interaction.list_scroll = clamp(
        editor.sdf_obstacle_interaction.list_scroll,
        0,
        sdf_obstacle_list_scroll_max(editor),
    )
}

sdf_obstacle_list_reveal_selected :: proc(editor: ^Editor) {
    if editor == nil do return
    selected := editor.sdf_obstacle_selected
    if selected < 0 {
        sdf_obstacle_list_scroll_clamp(editor)
        return
    }
    first := editor.sdf_obstacle_interaction.list_scroll
    if selected < first {
        editor.sdf_obstacle_interaction.list_scroll = selected
    } else if selected >= first + SDF_OBSTACLE_LIST_VISIBLE_COUNT {
        editor.sdf_obstacle_interaction.list_scroll = selected - SDF_OBSTACLE_LIST_VISIBLE_COUNT + 1
    }
    sdf_obstacle_list_scroll_clamp(editor)
}

sdf_obstacle_scroll :: proc(editor: ^Editor, delta: int) {
    if editor == nil || delta == 0 do return
    editor.sdf_obstacle_interaction.list_scroll += delta
    sdf_obstacle_list_scroll_clamp(editor)
}

sdf_obstacle_add_at :: proc(editor: ^Editor, position: flight.Vec3) -> int {
    count := sdf_obstacle_active_count(editor)
    if editor == nil || count >= len(editor.sdf_obstacles) do return -1
    editor.sdf_obstacles[count] = sdf_obstacle_default(position, count)
    editor.sdf_obstacle_count = count + 1
    _ = sdf_obstacle_select(editor, count)
    return count
}

sdf_obstacle_add :: proc(editor: ^Editor) -> int {
    if editor == nil do return -1
    x, z := editor.camera_pose.target.x, editor.camera_pose.target.z
    y := terrain.sample_surface_height(&editor.project, 0, x, z)
    if editor.cursor_hit {
        x, z, y = editor.cursor_world_x, editor.cursor_world_z, editor.cursor_height
    }
    return sdf_obstacle_add_at(editor, {x, y + SDF_OBSTACLE_DEFAULT_TUBE_RADIUS, z})
}

sdf_obstacle_delete_selected :: proc(editor: ^Editor) -> bool {
    count := sdf_obstacle_active_count(editor)
    if editor == nil || editor.sdf_obstacle_selected < 0 || editor.sdf_obstacle_selected >= count do return false
    removed := editor.sdf_obstacle_selected
    for index in removed ..< count - 1 do editor.sdf_obstacles[index] = editor.sdf_obstacles[index + 1]
    editor.sdf_obstacles[count - 1] = {}
    editor.sdf_obstacle_count = count - 1
    editor.sdf_obstacle_selected = editor.sdf_obstacle_count > 0 ? min(removed, editor.sdf_obstacle_count - 1) : -1
    editor.sdf_obstacle_interaction.hovered = -1
    if editor.sdf_obstacle_selected >= 0 {
        _ = sdf_obstacle_inspector_euler_refresh(editor)
    } else {
        editor.sdf_obstacle_interaction.inspector_euler_valid = false
    }
    sdf_obstacle_list_reveal_selected(editor)
    return true
}

sdf_obstacle_world_distance :: proc(obstacle: SDF_Torus_Obstacle, point: third_person.Vec3) -> f32 {
    if !fixture_editor_sdf_obstacle_valid(obstacle) do return f32(1.0e30)
    basis := flight.basis_from_orientation(obstacle.rotation)
    relative := flight.world_to_local(basis, point - obstacle.position)
    local := flight.Vec3{relative.x / obstacle.scale.x, relative.y / obstacle.scale.y, relative.z / obstacle.scale.z}
    radial := f32(math.sqrt(f64(local.x * local.x + local.z * local.z)))
    ring := radial - obstacle.major_radius
    local_distance := f32(math.sqrt(f64(ring * ring + local.y * local.y))) - obstacle.tube_radius
    return local_distance * min(obstacle.scale.x, min(obstacle.scale.y, obstacle.scale.z))
}

sdf_obstacle_ray_hit :: proc(
    obstacle: SDF_Torus_Obstacle,
    origin, direction: third_person.Vec3,
    maximum_distance: f32,
) -> (
    distance: f32,
    hit: bool,
) {
    if maximum_distance <= 0 || !fixture_editor_sdf_obstacle_valid(obstacle) do return
    if linalg.dot(direction, direction) <= 1e-8 do return
    for _ in 0 ..< SDF_OBSTACLE_RAY_MAX_STEPS {
        if distance > maximum_distance do return
        signed_distance := sdf_obstacle_world_distance(obstacle, origin + direction * distance)
        if math.abs(signed_distance) <= SDF_OBSTACLE_RAY_HIT_EPSILON {
            hit = true
            return
        }
        distance += max(math.abs(signed_distance) * .65, f32(.03))
    }
    return
}

sdf_obstacle_pick_ray :: proc(
    editor: ^Editor,
    origin, direction: third_person.Vec3,
    maximum_distance: f32 = terrain.WORLD_SIZE_METERS * 2,
) -> int {
    count := sdf_obstacle_active_count(editor)
    closest := maximum_distance
    selected := -1
    for index in 0 ..< count {
        distance, hit := sdf_obstacle_ray_hit(editor.sdf_obstacles[index], origin, direction, closest)
        if hit && distance < closest {
            closest = distance
            selected = index
        }
    }
    return selected
}

sdf_obstacle_process_input :: proc(
    editor: ^Editor,
    camera: Perspective_Camera,
    mouse: canvas2d.Vector2,
    width, height: i32,
    enabled: bool,
) -> bool {
    if editor == nil || editor.in_map || editor.authoring_tool != .Obstacles do return false
    if !enabled {
        editor.sdf_obstacle_interaction.hovered = -1
        return true
    }
    direction, ray_ok := editor_world_ray_direction(camera, mouse, width, height)
    hovered := ray_ok ? sdf_obstacle_pick_ray(editor, camera.position, direction) : -1
    editor.sdf_obstacle_interaction.hovered = hovered
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        if hovered >= 0 {
            _ = sdf_obstacle_select(editor, hovered)
        } else {
            _ = sdf_obstacle_add(editor)
        }
    }
    return true
}

sdf_obstacle_color :: #force_inline proc(obstacle: SDF_Torus_Obstacle, selected: bool) -> canvas2d.Color {
    color := canvas2d.Color{obstacle.color[0], obstacle.color[1], obstacle.color[2], obstacle.color[3]}
    if !selected do return color
    return {
        u8(clamp(f32(color.r) * 1.16 + 20, 0, 255)),
        u8(clamp(f32(color.g) * 1.16 + 20, 0, 255)),
        u8(clamp(f32(color.b) * 1.16 + 20, 0, 255)),
        255,
    }
}

sdf_obstacle_world_point :: proc(obstacle: SDF_Torus_Obstacle, local: flight.Vec3) -> third_person.Vec3 {
    scaled := flight.Vec3{local.x * obstacle.scale.x, local.y * obstacle.scale.y, local.z * obstacle.scale.z}
    return obstacle.position + linalg.mul(flight.normalize_orientation(obstacle.rotation), scaled)
}

sdf_obstacle_world_normal :: proc(obstacle: SDF_Torus_Obstacle, local: flight.Vec3) -> third_person.Vec3 {
    scaled := flight.Vec3{local.x / obstacle.scale.x, local.y / obstacle.scale.y, local.z / obstacle.scale.z}
    return linalg.normalize0(linalg.mul(flight.normalize_orientation(obstacle.rotation), scaled))
}

world_sdf_obstacles :: proc(editor: ^Editor) {
    count := sdf_obstacle_active_count(editor)
    for obstacle_index in 0 ..< count {
        obstacle := editor.sdf_obstacles[obstacle_index]
        if !fixture_editor_sdf_obstacle_valid(obstacle) do continue
        selected := !editor.in_map && obstacle_index == editor.sdf_obstacle_selected
        color := sdf_obstacle_color(obstacle, selected)
        for major_segment in 0 ..< SDF_TORUS_MAJOR_SEGMENTS {
            next_major := (major_segment + 1) % SDF_TORUS_MAJOR_SEGMENTS
            major_angle := f32(major_segment) * 2 * math.PI / f32(SDF_TORUS_MAJOR_SEGMENTS)
            next_major_angle := f32(next_major) * 2 * math.PI / f32(SDF_TORUS_MAJOR_SEGMENTS)
            for tube_segment in 0 ..< SDF_TORUS_TUBE_SEGMENTS {
                next_tube := (tube_segment + 1) % SDF_TORUS_TUBE_SEGMENTS
                tube_angle := f32(tube_segment) * 2 * math.PI / f32(SDF_TORUS_TUBE_SEGMENTS)
                next_tube_angle := f32(next_tube) * 2 * math.PI / f32(SDF_TORUS_TUBE_SEGMENTS)
                local_points := [4]flight.Vec3 {
                    sdf_obstacle_torus_point(obstacle, major_angle, tube_angle),
                    sdf_obstacle_torus_point(obstacle, next_major_angle, tube_angle),
                    sdf_obstacle_torus_point(obstacle, next_major_angle, next_tube_angle),
                    sdf_obstacle_torus_point(obstacle, major_angle, next_tube_angle),
                }
                local_normals := [4]flight.Vec3 {
                    sdf_obstacle_torus_normal(major_angle, tube_angle),
                    sdf_obstacle_torus_normal(next_major_angle, tube_angle),
                    sdf_obstacle_torus_normal(next_major_angle, next_tube_angle),
                    sdf_obstacle_torus_normal(major_angle, next_tube_angle),
                }
                points: [4]third_person.Vec3
                normals: [4]third_person.Vec3
                for index in 0 ..< len(points) {
                    points[index] = sdf_obstacle_world_point(obstacle, local_points[index])
                    normals[index] = sdf_obstacle_world_normal(obstacle, local_normals[index])
                }
                world_triangle_smooth_lit(
                    points[0],
                    points[2],
                    points[1],
                    normals[0],
                    normals[2],
                    normals[1],
                    color,
                    color,
                    color,
                    .82,
                )
                world_triangle_smooth_lit(
                    points[0],
                    points[3],
                    points[2],
                    normals[0],
                    normals[3],
                    normals[2],
                    color,
                    color,
                    color,
                    .82,
                )
            }
        }
    }
}

sdf_obstacle_torus_point :: #force_inline proc(
    obstacle: SDF_Torus_Obstacle,
    major_angle, tube_angle: f32,
) -> flight.Vec3 {
    radial := obstacle.major_radius + obstacle.tube_radius * math.cos(tube_angle)
    return {
        radial * math.cos(major_angle),
        obstacle.tube_radius * math.sin(tube_angle),
        radial * math.sin(major_angle),
    }
}

sdf_obstacle_torus_normal :: #force_inline proc(major_angle, tube_angle: f32) -> flight.Vec3 {
    return {
        math.cos(major_angle) * math.cos(tube_angle),
        math.sin(tube_angle),
        math.sin(major_angle) * math.cos(tube_angle),
    }
}
