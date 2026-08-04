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
SDF_OBSTACLE_GIZMO_HANDLE_PIXELS :: f32(12)
SDF_OBSTACLE_GIZMO_AXIS_PIXELS :: f32(48)
SDF_OBSTACLE_ROTATION_RING_PIXELS :: f32(72)
SDF_OBSTACLE_GIZMO_STROKE_PIXELS :: f32(4)
SDF_OBSTACLE_ROTATION_RING_SEGMENTS :: 48
SDF_OBSTACLE_GIZMO_ACTIVE_COLOR :: canvas2d.Color{232, 216, 108, 255}
SDF_OBSTACLE_SCALE_HANDLE_PIXELS :: f32(104)
SDF_OBSTACLE_SCALE_HANDLE_SIZE_PIXELS :: f32(14)
SDF_OBSTACLE_FREE_SCALE_PIXELS :: f32(160)
SDF_OBSTACLE_INITIAL_RADIUS_PIXELS :: f32(96)
SDF_OBSTACLE_SCALE_REFERENCE_RADIUS_PIXELS :: SDF_OBSTACLE_INITIAL_RADIUS_PIXELS
SDF_OBSTACLE_SCALE_MIN_ZOOM_FACTOR :: f32(.35)
SDF_OBSTACLE_SCALE_MAX_ZOOM_FACTOR :: f32(6)

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

sdf_obstacle_set_rotation :: proc(editor: ^Editor, rotation: quaternion128) -> bool {
    obstacle := sdf_obstacle_selected_ptr(editor)
    if obstacle == nil || !fixture_editor_orientation_valid(rotation) do return false
    obstacle.rotation = flight.normalize_orientation(rotation)
    return sdf_obstacle_inspector_euler_refresh(editor)
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
    world_width, world_height := canvas2d.GetWorldRenderSize()
    focal_length := editor.vehicle_showcase_scene ? VEHICLE_SHOWCASE_FOCAL_LENGTH : f32(1.35)
    camera := perspective_camera(editor.camera_pose, focal_length)
    initial_scale := sdf_obstacle_initial_scale(camera, {x, y, z}, world_width, world_height)
    index := sdf_obstacle_add_at(editor, {x, y + SDF_OBSTACLE_DEFAULT_TUBE_RADIUS * initial_scale, z})
    if index >= 0 {
        editor.sdf_obstacles[index].scale = {initial_scale, initial_scale, initial_scale}
    }
    return index
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

sdf_obstacle_gizmo_screen_size :: proc(camera: Perspective_Camera, position: flight.Vec3, pixels: f32, width, height: i32) -> f32 {
    if height <= 0 || camera.focal_length <= 0 do return 0
    depth := linalg.dot(position - camera.position, camera.forward)
    if depth <= .08 do return 0
    return pixels * depth * 2 / (camera.focal_length * f32(height))
}

sdf_obstacle_projected_radius_pixels :: proc(camera: Perspective_Camera, position: flight.Vec3, radius: f32, height: i32) -> f32 {
    if height <= 0 || camera.focal_length <= 0 || radius <= 0 do return 0
    depth := linalg.dot(position - camera.position, camera.forward)
    if depth <= .08 do return 0
    return radius * camera.focal_length * f32(height) / (2 * depth)
}

sdf_obstacle_projected_outer_radius_pixels :: proc(camera: Perspective_Camera, obstacle: SDF_Torus_Obstacle, height: i32) -> f32 {
    outer_radius := (obstacle.major_radius + obstacle.tube_radius) * max(obstacle.scale.x, max(obstacle.scale.y, obstacle.scale.z))
    return sdf_obstacle_projected_radius_pixels(camera, obstacle.position, outer_radius, height)
}

sdf_obstacle_scale_zoom_factor :: proc(camera: Perspective_Camera, obstacle: SDF_Torus_Obstacle, height: i32) -> f32 {
    projected_radius := sdf_obstacle_projected_outer_radius_pixels(camera, obstacle, height)
    if projected_radius <= .001 do return 1
    return clamp(
        SDF_OBSTACLE_SCALE_REFERENCE_RADIUS_PIXELS / projected_radius,
        SDF_OBSTACLE_SCALE_MIN_ZOOM_FACTOR,
        SDF_OBSTACLE_SCALE_MAX_ZOOM_FACTOR,
    )
}

sdf_obstacle_initial_scale :: proc(camera: Perspective_Camera, position: flight.Vec3, width, height: i32) -> f32 {
    world_radius := sdf_obstacle_gizmo_screen_size(camera, position, SDF_OBSTACLE_INITIAL_RADIUS_PIXELS, width, height)
    default_outer_radius := SDF_OBSTACLE_DEFAULT_MAJOR_RADIUS + SDF_OBSTACLE_DEFAULT_TUBE_RADIUS
    if world_radius <= 0 || default_outer_radius <= 0 do return 1
    return clamp(
        world_radius / default_outer_radius,
        SDF_OBSTACLE_MINIMUM_SCALE,
        SDF_OBSTACLE_MAXIMUM_SCALE,
    )
}

sdf_obstacle_gizmo_size :: proc(camera: Perspective_Camera, position: flight.Vec3, width, height: i32) -> f32 {
    return sdf_obstacle_gizmo_screen_size(camera, position, SDF_OBSTACLE_GIZMO_AXIS_PIXELS, width, height)
}

sdf_obstacle_rotation_ring_radius :: proc(camera: Perspective_Camera, position: flight.Vec3, width, height: i32) -> f32 {
    return sdf_obstacle_gizmo_screen_size(camera, position, SDF_OBSTACLE_ROTATION_RING_PIXELS, width, height)
}

sdf_obstacle_scale_handle_radius :: proc(camera: Perspective_Camera, position: flight.Vec3, width, height: i32) -> f32 {
    return sdf_obstacle_gizmo_screen_size(camera, position, SDF_OBSTACLE_SCALE_HANDLE_PIXELS, width, height)
}

sdf_obstacle_scale_handle_size :: proc(camera: Perspective_Camera, position: flight.Vec3, width, height: i32) -> f32 {
    return sdf_obstacle_gizmo_screen_size(camera, position, SDF_OBSTACLE_SCALE_HANDLE_SIZE_PIXELS, width, height)
}

sdf_obstacle_gizmo_stroke_size :: proc(camera: Perspective_Camera, position: flight.Vec3, width, height: i32) -> f32 {
    return sdf_obstacle_gizmo_screen_size(camera, position, SDF_OBSTACLE_GIZMO_STROKE_PIXELS, width, height)
}

sdf_obstacle_axis_vector :: proc(axis: SDF_Obstacle_Axis) -> flight.Vec3 {
    switch axis {
    case .None: return {}
    case .X: return {1, 0, 0}
    case .Y: return {0, 1, 0}
    case .Z: return {0, 0, 1}
    }
    return {}
}

sdf_obstacle_ray_plane_point :: proc(origin, direction, plane_point, plane_normal: flight.Vec3) -> (flight.Vec3, bool) {
    denominator := linalg.dot(direction, plane_normal)
    if math.abs(denominator) <= .0001 do return {}, false
    distance := linalg.dot(plane_point - origin, plane_normal) / denominator
    if distance < 0 do return {}, false
    return origin + direction * distance, true
}

sdf_obstacle_gizmo_axis_color :: #force_inline proc(axis: SDF_Obstacle_Axis) -> canvas2d.Color {
    switch axis {
    case .None: return {}
    case .X: return {224, 80, 72, 255}
    case .Y: return {92, 190, 96, 255}
    case .Z: return {76, 132, 224, 255}
    }
    return {}
}

sdf_obstacle_gizmo_axis_render_color :: #force_inline proc(mode: SDF_Obstacle_Gizmo_Mode, constrained_axis, axis: SDF_Obstacle_Axis) -> canvas2d.Color {
    if (mode == .Translate || mode == .Rotate) && constrained_axis == axis && axis != .None do return SDF_OBSTACLE_GIZMO_ACTIVE_COLOR
    return sdf_obstacle_gizmo_axis_color(axis)
}

sdf_obstacle_scale_handle_color :: #force_inline proc(mode: SDF_Obstacle_Gizmo_Mode, constrained_axis, axis: SDF_Obstacle_Axis) -> canvas2d.Color {
    if mode == .Scale && constrained_axis == axis && axis != .None do return SDF_OBSTACLE_GIZMO_ACTIVE_COLOR
    return sdf_obstacle_gizmo_axis_color(axis)
}

sdf_obstacle_gizmo_center_active :: #force_inline proc(mode: SDF_Obstacle_Gizmo_Mode, constrained_axis: SDF_Obstacle_Axis) -> bool {
    return mode == .None || constrained_axis == .None
}

sdf_obstacle_axis_drag_point :: proc(origin, axis_direction, ray_origin, ray_direction: flight.Vec3) -> (flight.Vec3, bool) {
    if !(linalg.dot(axis_direction, axis_direction) > .0001) do return {}, false
    axis := linalg.normalize0(axis_direction)
    parallel := linalg.dot(ray_direction, axis)
    denominator := 1 - parallel * parallel
    if denominator <= .0001 do return {}, false
    offset := ray_origin - origin
    ray_distance := (parallel * linalg.dot(axis, offset) - linalg.dot(ray_direction, offset)) / denominator
    if ray_distance < 0 do return {}, false
    axis_distance := linalg.dot(axis, offset + ray_direction * ray_distance)
    return origin + axis * axis_distance, true
}

sdf_obstacle_axis_drag_position :: proc(snapshot: flight.Vec3, axis: SDF_Obstacle_Axis, ray_origin, ray_direction: flight.Vec3) -> (flight.Vec3, bool) {
    return sdf_obstacle_axis_drag_point(snapshot, sdf_obstacle_axis_vector(axis), ray_origin, ray_direction)
}

sdf_obstacle_free_drag_position :: proc(snapshot, ray_origin, ray_direction, camera_forward: flight.Vec3) -> (flight.Vec3, bool) {
    return sdf_obstacle_ray_plane_point(ray_origin, ray_direction, snapshot, camera_forward)
}

sdf_obstacle_modal_active :: #force_inline proc(editor: ^Editor) -> bool {
    return editor != nil && editor.sdf_obstacle_interaction.gizmo_mode != .None && editor.sdf_obstacle_interaction.transform_snapshot_valid
}

sdf_obstacle_modal_selection_matches :: #force_inline proc(editor: ^Editor) -> bool {
    return sdf_obstacle_modal_active(editor) &&
        editor.sdf_obstacle_selected == editor.sdf_obstacle_interaction.transform_snapshot_slot
}

sdf_obstacle_modal_finish :: proc(editor: ^Editor, cancel: bool) {
    if editor == nil do return
    interaction := &editor.sdf_obstacle_interaction
    if cancel && interaction.transform_snapshot_valid {
        slot := interaction.transform_snapshot_slot
        if slot >= 0 && slot < sdf_obstacle_active_count(editor) {
            editor.sdf_obstacles[slot] = interaction.transform_snapshot
            if editor.sdf_obstacle_selected == slot do _ = sdf_obstacle_inspector_euler_refresh(editor)
        }
    }
    interaction.gizmo_mode = .None
    interaction.constrained_axis = .None
    interaction.drag_anchor_world = {}
    interaction.drag_anchor_screen = {}
    interaction.transform_snapshot = {}
    interaction.transform_snapshot_valid = false
    interaction.transform_snapshot_slot = -1
}

sdf_obstacle_modal_begin :: proc(editor: ^Editor, mode: SDF_Obstacle_Gizmo_Mode, axis: SDF_Obstacle_Axis) -> bool {
    obstacle := sdf_obstacle_selected_ptr(editor)
    if editor == nil || obstacle == nil || sdf_obstacle_modal_active(editor) do return false
    interaction := &editor.sdf_obstacle_interaction
    interaction.gizmo_mode = mode
    interaction.constrained_axis = axis
    interaction.transform_snapshot = obstacle^
    interaction.transform_snapshot_valid = true
    interaction.transform_snapshot_slot = editor.sdf_obstacle_selected
    interaction.drag_anchor_world = {math.QNAN_F32, math.QNAN_F32, math.QNAN_F32}
    interaction.drag_anchor_screen = {math.QNAN_F32, math.QNAN_F32}
    return true
}

sdf_obstacle_rotation_angle :: proc(camera: Perspective_Camera, mouse: canvas2d.Vector2, position: flight.Vec3, width, height: i32) -> (f32, bool) {
    center := project_3d(camera, position, width, height)
    if !center.visible do return 0, false
    x, y := mouse.x - center.position.x, mouse.y - center.position.y
    if x*x + y*y < 16 do return 0, false
    return f32(math.atan2(f64(y), f64(x))), true
}

sdf_obstacle_rotation_delta :: proc(from, to: f32) -> f32 {
    return f32(math.atan2(f64(math.sin(to-from)), f64(math.cos(to-from))))
}

sdf_obstacle_rotation_axis_update :: proc(editor: ^Editor, camera: Perspective_Camera, mouse: canvas2d.Vector2, width, height: i32) -> bool {
    interaction := &editor.sdf_obstacle_interaction
    snapshot := interaction.transform_snapshot
    local_axis := sdf_obstacle_axis_vector(interaction.constrained_axis)
    world_axis := linalg.mul(flight.normalize_orientation(snapshot.rotation), local_axis)
    direction, ray_ok := editor_world_ray_direction(camera, mouse, width, height)
    point, point_ok := sdf_obstacle_ray_plane_point(camera.position, direction, snapshot.position, world_axis)
    if !ray_ok || !point_ok do return true
    radial := point - snapshot.position
    if !(linalg.dot(radial, radial) > .0001) do return true
    if !fixture_editor_vec3_finite(interaction.drag_anchor_world) {
        interaction.drag_anchor_world = point
        return true
    }
    anchor_radial := interaction.drag_anchor_world - snapshot.position
    if !(linalg.dot(anchor_radial, anchor_radial) > .0001) do return true
    delta := f32(math.atan2(
        f64(linalg.dot(world_axis, linalg.cross(anchor_radial, radial))),
        f64(linalg.dot(anchor_radial, radial)),
    ))
    local_delta := linalg.quaternion_angle_axis(delta, local_axis)
    return sdf_obstacle_set_rotation(editor, linalg.mul(snapshot.rotation, local_delta))
}

sdf_obstacle_rotation_update :: proc(editor: ^Editor, camera: Perspective_Camera, mouse: canvas2d.Vector2, width, height: i32) -> bool {
    if !sdf_obstacle_modal_selection_matches(editor) do return false
    interaction := &editor.sdf_obstacle_interaction
    if interaction.constrained_axis != .None do return sdf_obstacle_rotation_axis_update(editor, camera, mouse, width, height)
    angle, ok := sdf_obstacle_rotation_angle(camera, mouse, interaction.transform_snapshot.position, width, height)
    if !ok do return false
    if !fixture_editor_scalar_finite(interaction.drag_anchor_screen[0]) {
        interaction.drag_anchor_screen[0] = angle
        return true
    }
    // Projected screen Y grows downward, unlike the right-handed world frame.
    // Negating keeps a clockwise cursor motion visibly clockwise around view.
    delta := -sdf_obstacle_rotation_delta(interaction.drag_anchor_screen[0], angle)
    snapshot := interaction.transform_snapshot.rotation
    view_delta := linalg.quaternion_angle_axis(delta, camera.forward)
    return sdf_obstacle_set_rotation(editor, linalg.mul(view_delta, snapshot))
}

sdf_obstacle_rotation_set_axis :: proc(editor: ^Editor, axis: SDF_Obstacle_Axis) -> bool {
    if !sdf_obstacle_modal_selection_matches(editor) do return false
    editor.sdf_obstacle_interaction.constrained_axis = axis
    editor.sdf_obstacle_interaction.drag_anchor_world = {math.QNAN_F32, math.QNAN_F32, math.QNAN_F32}
    editor.sdf_obstacle_interaction.drag_anchor_screen = {math.QNAN_F32, math.QNAN_F32}
    return true
}

sdf_obstacle_rotation_ring_hit :: proc(camera: Perspective_Camera, mouse: canvas2d.Vector2, obstacle: SDF_Torus_Obstacle, radius: f32, width, height: i32) -> (SDF_Obstacle_Axis, bool) {
    best := SDF_OBSTACLE_GIZMO_HANDLE_PIXELS
    result := SDF_Obstacle_Axis.None
    rotation := flight.normalize_orientation(obstacle.rotation)
    if !project_3d(camera, obstacle.position, width, height).visible do return .None, false
    axes := [3]SDF_Obstacle_Axis{.X, .Y, .Z}
    for axis in axes {
        local_axis := sdf_obstacle_axis_vector(axis)
        u := math.abs(local_axis.y) < .9 ? linalg.normalize0(linalg.cross(local_axis, flight.Vec3{0, 1, 0})) : flight.Vec3{1, 0, 0}
        v := linalg.cross(local_axis, u)
        for segment in 0 ..< SDF_OBSTACLE_ROTATION_RING_SEGMENTS {
            angle := f32(segment) * 2 * math.PI / f32(SDF_OBSTACLE_ROTATION_RING_SEGMENTS)
            point := obstacle.position + linalg.mul(rotation, (u * math.cos(angle) + v * math.sin(angle)) * radius)
            projected := project_3d(camera, point, width, height)
            if !projected.visible do continue
            dx, dy := mouse.x-projected.position.x, mouse.y-projected.position.y
            distance := math.sqrt(dx*dx + dy*dy)
            if distance < best { best = distance; result = axis }
        }
    }
    return result, result != .None
}

sdf_obstacle_modal_set_axis :: proc(
    editor: ^Editor,
    axis: SDF_Obstacle_Axis,
    camera: Perspective_Camera,
    direction: flight.Vec3,
) -> bool {
    if !sdf_obstacle_modal_selection_matches(editor) do return false
    snapshot := editor.sdf_obstacle_interaction.transform_snapshot.position
    anchor, solved := sdf_obstacle_axis_drag_position(snapshot, axis, camera.position, direction)
    if !solved do return false
    editor.sdf_obstacle_interaction.constrained_axis = axis
    editor.sdf_obstacle_interaction.drag_anchor_world = anchor
    return true
}

sdf_obstacle_modal_start_allowed :: #force_inline proc(editor: ^Editor, ray_ok: bool) -> bool {
    return ray_ok && sdf_obstacle_selected_ptr(editor) != nil
}

sdf_obstacle_gizmo_hit_test :: proc(
    camera: Perspective_Camera,
    mouse: canvas2d.Vector2,
    position: flight.Vec3,
    size: f32,
    width, height: i32,
) -> (axis: SDF_Obstacle_Axis, hit: bool) {
    center := project_3d(camera, position, width, height)
    if !center.visible do return .None, false
    delta_x, delta_y := mouse.x - center.position.x, mouse.y - center.position.y
    if delta_x * delta_x + delta_y * delta_y <= SDF_OBSTACLE_GIZMO_HANDLE_PIXELS * SDF_OBSTACLE_GIZMO_HANDLE_PIXELS do return .None, true
    best_distance := SDF_OBSTACLE_GIZMO_HANDLE_PIXELS
    result_axis := SDF_Obstacle_Axis.None
    axes := [3]SDF_Obstacle_Axis{.X, .Y, .Z}
    for handle_axis in axes {
        endpoint := project_3d(camera, position + sdf_obstacle_axis_vector(handle_axis) * size, width, height)
        if !endpoint.visible do continue
        segment_x, segment_y := endpoint.position.x - center.position.x, endpoint.position.y - center.position.y
        length_squared := segment_x * segment_x + segment_y * segment_y
        if length_squared <= 1 do continue
        t := clamp((delta_x * segment_x + delta_y * segment_y) / length_squared, f32(.2), f32(1))
        closest_x, closest_y := center.position.x + segment_x * t, center.position.y + segment_y * t
        distance_x, distance_y := mouse.x - closest_x, mouse.y - closest_y
        distance := math.sqrt(distance_x * distance_x + distance_y * distance_y)
        if distance < best_distance {
            best_distance = distance
            result_axis = handle_axis
        }
    }
    return result_axis, result_axis != .None
}

sdf_obstacle_modal_update :: proc(editor: ^Editor, camera: Perspective_Camera, direction: flight.Vec3) -> bool {
    if !sdf_obstacle_modal_selection_matches(editor) do return false
    snapshot := editor.sdf_obstacle_interaction.transform_snapshot.position
    axis := editor.sdf_obstacle_interaction.constrained_axis
    position: flight.Vec3
    solved: bool
    if axis == .None {
        position, solved = sdf_obstacle_free_drag_position(snapshot, camera.position, direction, camera.forward)
    } else {
        position, solved = sdf_obstacle_axis_drag_position(snapshot, axis, camera.position, direction)
    }
    if !solved do return false
    interaction := &editor.sdf_obstacle_interaction
    if !fixture_editor_vec3_finite(interaction.drag_anchor_world) {
        interaction.drag_anchor_world = position
        return true
    }
    return sdf_obstacle_set_position(editor, snapshot + position - interaction.drag_anchor_world)
}

sdf_obstacle_scale_with_axis :: proc(scale: flight.Vec3, axis: SDF_Obstacle_Axis, multiplier: f32) -> flight.Vec3 {
    result := scale
    switch axis {
    case .X: result.x *= multiplier
    case .Y: result.y *= multiplier
    case .Z: result.z *= multiplier
    case .None:
    }
    return result
}

sdf_obstacle_scale_component :: proc(scale: flight.Vec3, axis: SDF_Obstacle_Axis) -> f32 {
    switch axis {
    case .X: return scale.x
    case .Y: return scale.y
    case .Z: return scale.z
    case .None: return 0
    }
    return 0
}

sdf_obstacle_scale_axis_update :: proc(editor: ^Editor, camera: Perspective_Camera, direction: flight.Vec3, width, height: i32) -> bool {
    if !sdf_obstacle_modal_selection_matches(editor) do return false
    interaction := &editor.sdf_obstacle_interaction
    snapshot := interaction.transform_snapshot
    local_axis := sdf_obstacle_axis_vector(interaction.constrained_axis)
    world_axis := linalg.mul(flight.normalize_orientation(snapshot.rotation), local_axis)
    point, solved := sdf_obstacle_axis_drag_point(snapshot.position, world_axis, camera.position, direction)
    if !solved do return true
    if !fixture_editor_vec3_finite(interaction.drag_anchor_world) {
        interaction.drag_anchor_world = point
        obstacle := sdf_obstacle_selected_ptr(editor)
        if obstacle == nil do return false
        interaction.drag_anchor_screen[0] = sdf_obstacle_scale_component(obstacle.scale, interaction.constrained_axis)
        return true
    }
    radius := sdf_obstacle_scale_handle_radius(camera, snapshot.position, width, height)
    if !(radius > .0001) do return true
    anchor_distance := linalg.dot(world_axis, interaction.drag_anchor_world - snapshot.position)
    current_distance := linalg.dot(world_axis, point - snapshot.position)
    zoom_factor := sdf_obstacle_scale_zoom_factor(camera, snapshot, height)
    multiplier := clamp(
        1 + (current_distance - anchor_distance) / radius * zoom_factor,
        f32(.001),
        f32(128),
    )
    axis_baseline := interaction.drag_anchor_screen[0]
    if !fixture_editor_scalar_finite(axis_baseline) do return false
    obstacle := sdf_obstacle_selected_ptr(editor)
    if obstacle == nil do return false
    result := obstacle.scale
    switch interaction.constrained_axis {
    case .X: result.x = axis_baseline * multiplier
    case .Y: result.y = axis_baseline * multiplier
    case .Z: result.z = axis_baseline * multiplier
    case .None: return false
    }
    return sdf_obstacle_set_scale(editor, result)
}

sdf_obstacle_scale_free_update :: proc(editor: ^Editor, camera: Perspective_Camera, mouse: canvas2d.Vector2, width, height: i32) -> bool {
    if !sdf_obstacle_modal_selection_matches(editor) do return false
    interaction := &editor.sdf_obstacle_interaction
    if !fixture_editor_scalar_finite(interaction.drag_anchor_screen[0]) {
        interaction.drag_anchor_screen = {mouse.x, mouse.y}
        return true
    }
    pixels := mouse.x - interaction.drag_anchor_screen[0] + interaction.drag_anchor_screen[1] - mouse.y
    zoom_factor := sdf_obstacle_scale_zoom_factor(camera, interaction.transform_snapshot, height)
    multiplier := clamp(1 + pixels / SDF_OBSTACLE_FREE_SCALE_PIXELS * zoom_factor, f32(.001), f32(128))
    return sdf_obstacle_set_scale(editor, interaction.transform_snapshot.scale * multiplier)
}

sdf_obstacle_scale_update :: proc(editor: ^Editor, camera: Perspective_Camera, direction: flight.Vec3, mouse: canvas2d.Vector2, width, height: i32) -> bool {
    if editor == nil do return false
    if editor.sdf_obstacle_interaction.constrained_axis == .None {
        return sdf_obstacle_scale_free_update(editor, camera, mouse, width, height)
    }
    return sdf_obstacle_scale_axis_update(editor, camera, direction, width, height)
}

sdf_obstacle_scale_set_axis :: proc(editor: ^Editor, axis: SDF_Obstacle_Axis) -> bool {
    if !sdf_obstacle_modal_selection_matches(editor) do return false
    interaction := &editor.sdf_obstacle_interaction
    interaction.constrained_axis = axis
    interaction.drag_anchor_world = {math.QNAN_F32, math.QNAN_F32, math.QNAN_F32}
    interaction.drag_anchor_screen = {math.QNAN_F32, math.QNAN_F32}
    return true
}

sdf_obstacle_scale_gizmo_hit :: proc(camera: Perspective_Camera, mouse: canvas2d.Vector2, obstacle: SDF_Torus_Obstacle, radius: f32, width, height: i32) -> (SDF_Obstacle_Axis, bool) {
    best := SDF_OBSTACLE_GIZMO_HANDLE_PIXELS
    result := SDF_Obstacle_Axis.None
    rotation := flight.normalize_orientation(obstacle.rotation)
    axes := [3]SDF_Obstacle_Axis{.X, .Y, .Z}
    for axis in axes {
        world_axis := linalg.mul(rotation, sdf_obstacle_axis_vector(axis))
        endpoint := project_3d(camera, obstacle.position + world_axis * radius, width, height)
        if !endpoint.visible do continue
        dx, dy := mouse.x-endpoint.position.x, mouse.y-endpoint.position.y
        distance := math.sqrt(dx*dx + dy*dy)
        if distance < best { best = distance; result = axis }
    }
    return result, result != .None
}

sdf_obstacle_process_input :: proc(
    editor: ^Editor,
    camera: Perspective_Camera,
    mouse: canvas2d.Vector2,
    width, height: i32,
    enabled: bool,
) -> bool {
    if editor == nil do return false
    if editor.in_map || editor.authoring_tool != .Obstacles {
        if sdf_obstacle_modal_active(editor) do sdf_obstacle_modal_finish(editor, true)
        return false
    }
    if !enabled {
        editor.sdf_obstacle_interaction.hovered = -1
        if sdf_obstacle_modal_active(editor) do sdf_obstacle_modal_finish(editor, true)
        return true
    }
    direction, ray_ok := editor_world_ray_direction(camera, mouse, width, height)
    if sdf_obstacle_modal_active(editor) {
        if editor.sdf_obstacle_interaction.gizmo_mode == .Rotate {
            if !sdf_obstacle_modal_selection_matches(editor) ||
               canvas2d.IsKeyPressed(.ESCAPE) ||
               canvas2d.IsMouseButtonPressed(.RIGHT) ||
               !ray_ok {
                sdf_obstacle_modal_finish(editor, true)
            } else if canvas2d.IsMouseButtonReleased(.LEFT) {
                sdf_obstacle_modal_finish(editor, false)
            } else {
                axis_switch_failed :=
                    (canvas2d.IsKeyPressed(.X) && !sdf_obstacle_rotation_set_axis(editor, .X)) ||
                    (canvas2d.IsKeyPressed(.Y) && !sdf_obstacle_rotation_set_axis(editor, .Y)) ||
                    (canvas2d.IsKeyPressed(.Z) && !sdf_obstacle_rotation_set_axis(editor, .Z))
                if axis_switch_failed || !sdf_obstacle_rotation_update(editor, camera, mouse, width, height) do sdf_obstacle_modal_finish(editor, true)
            }
            return true
        }
        if editor.sdf_obstacle_interaction.gizmo_mode == .Scale {
            if !sdf_obstacle_modal_selection_matches(editor) ||
               canvas2d.IsKeyPressed(.ESCAPE) ||
               canvas2d.IsMouseButtonPressed(.RIGHT) ||
               !ray_ok {
                sdf_obstacle_modal_finish(editor, true)
            } else if canvas2d.IsMouseButtonReleased(.LEFT) {
                sdf_obstacle_modal_finish(editor, false)
            } else {
                axis_switch_failed :=
                    (canvas2d.IsKeyPressed(.X) && !sdf_obstacle_scale_set_axis(editor, .X)) ||
                    (canvas2d.IsKeyPressed(.Y) && !sdf_obstacle_scale_set_axis(editor, .Y)) ||
                    (canvas2d.IsKeyPressed(.Z) && !sdf_obstacle_scale_set_axis(editor, .Z))
                if axis_switch_failed || !sdf_obstacle_scale_update(editor, camera, direction, mouse, width, height) do sdf_obstacle_modal_finish(editor, true)
            }
            return true
        }
        if !sdf_obstacle_modal_selection_matches(editor) {
            sdf_obstacle_modal_finish(editor, true)
        } else if canvas2d.IsKeyPressed(.ESCAPE) || canvas2d.IsMouseButtonPressed(.RIGHT) {
            sdf_obstacle_modal_finish(editor, true)
        } else if canvas2d.IsMouseButtonReleased(.LEFT) {
            sdf_obstacle_modal_finish(editor, false)
        } else if !ray_ok {
            sdf_obstacle_modal_finish(editor, true)
        } else {
            axis_switch_failed :=
                (canvas2d.IsKeyPressed(.X) && !sdf_obstacle_modal_set_axis(editor, .X, camera, direction)) ||
                (canvas2d.IsKeyPressed(.Y) && !sdf_obstacle_modal_set_axis(editor, .Y, camera, direction)) ||
                (canvas2d.IsKeyPressed(.Z) && !sdf_obstacle_modal_set_axis(editor, .Z, camera, direction))
            if axis_switch_failed || !sdf_obstacle_modal_update(editor, camera, direction) do sdf_obstacle_modal_finish(editor, true)
        }
        return true
    }
    if canvas2d.IsKeyPressed(.G) && sdf_obstacle_modal_start_allowed(editor, ray_ok) && sdf_obstacle_modal_begin(editor, .Translate, .None) {
        _ = sdf_obstacle_modal_update(editor, camera, direction)
        return true
    }
    if canvas2d.IsKeyPressed(.R) && sdf_obstacle_modal_start_allowed(editor, ray_ok) && sdf_obstacle_modal_begin(editor, .Rotate, .None) {
        if !sdf_obstacle_rotation_update(editor, camera, mouse, width, height) do sdf_obstacle_modal_finish(editor, true)
        return true
    }
    if canvas2d.IsKeyPressed(.S) && sdf_obstacle_modal_start_allowed(editor, ray_ok) && sdf_obstacle_modal_begin(editor, .Scale, .None) {
        if !sdf_obstacle_scale_update(editor, camera, direction, mouse, width, height) do sdf_obstacle_modal_finish(editor, true)
        return true
    }
    if !ray_ok do return true
    obstacle := sdf_obstacle_selected_ptr(editor)
    if obstacle != nil && canvas2d.IsMouseButtonPressed(.LEFT) {
        size := sdf_obstacle_gizmo_size(camera, obstacle.position, width, height)
        ring_radius := sdf_obstacle_rotation_ring_radius(camera, obstacle.position, width, height)
        axis, gizmo_hit := sdf_obstacle_gizmo_hit_test(camera, mouse, obstacle.position, size, width, height)
        if gizmo_hit {
            _ = sdf_obstacle_modal_begin(editor, .Translate, axis)
            if !sdf_obstacle_modal_update(editor, camera, direction) do sdf_obstacle_modal_finish(editor, true)
            return true
        }
        ring_axis, ring_hit := sdf_obstacle_rotation_ring_hit(camera, mouse, obstacle^, ring_radius, width, height)
        if ring_hit {
            _ = sdf_obstacle_modal_begin(editor, .Rotate, ring_axis)
            if !sdf_obstacle_rotation_update(editor, camera, mouse, width, height) do sdf_obstacle_modal_finish(editor, true)
            return true
        }
        scale_radius := sdf_obstacle_scale_handle_radius(camera, obstacle.position, width, height)
        scale_axis, scale_hit := sdf_obstacle_scale_gizmo_hit(camera, mouse, obstacle^, scale_radius, width, height)
        if scale_hit {
            _ = sdf_obstacle_modal_begin(editor, .Scale, scale_axis)
            if !sdf_obstacle_scale_update(editor, camera, direction, mouse, width, height) do sdf_obstacle_modal_finish(editor, true)
            return true
        }
    }
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

sdf_obstacle_gizmo_triangle :: #force_inline proc(a, b, c: third_person.Vec3, color: canvas2d.Color) {
    world_triangle_material(a, b, c, color, .Unshaded)
}

sdf_obstacle_gizmo_quad :: #force_inline proc(a, b, c, d: third_person.Vec3, color: canvas2d.Color) {
    sdf_obstacle_gizmo_triangle(a, b, c, color)
    sdf_obstacle_gizmo_triangle(a, c, d, color)
}

sdf_obstacle_gizmo_box_between :: proc(a, b, forward: third_person.Vec3, width, depth: f32, color: canvas2d.Color) {
    delta := third_person.Vec3{b.x - a.x, b.y - a.y, b.z - a.z}
    length := linalg.length(delta)
    if length <= .0001 do return
    axis_y := delta / length
    axis_z := linalg.normalize0(forward)
    axis_x := linalg.cross(axis_y, axis_z)
    axis_x_length := linalg.length(axis_x)
    if axis_x_length <= .0001 {
        axis_z = linalg.cross(axis_y, third_person.Vec3{0, 1, 0})
        if linalg.length(axis_z) <= .0001 do axis_z = linalg.cross(axis_y, third_person.Vec3{1, 0, 0})
        axis_z = linalg.normalize0(axis_z)
        axis_x = linalg.cross(axis_y, axis_z)
        axis_x_length = linalg.length(axis_x)
    }
    if axis_x_length > .0001 {
        axis_x /= axis_x_length
    } else {
        axis_x = {1, 0, 0}
    }
    center := (a + b) * .5
    signs := [8][3]f32 {
        {-1, -1, -1}, {1, -1, -1}, {1, 1, -1}, {-1, 1, -1},
        {-1, -1, 1}, {1, -1, 1}, {1, 1, 1}, {-1, 1, 1},
    }
    points: [8]third_person.Vec3
    for index in 0 ..< len(points) {
        points[index] = center +
            axis_x * (signs[index][0] * width * .5) +
            axis_y * (signs[index][1] * length * .5) +
            axis_z * (signs[index][2] * depth * .5)
    }
    sdf_obstacle_gizmo_quad(points[0], points[3], points[2], points[1], color)
    sdf_obstacle_gizmo_quad(points[4], points[5], points[6], points[7], color)
    sdf_obstacle_gizmo_quad(points[0], points[4], points[7], points[3], color)
    sdf_obstacle_gizmo_quad(points[1], points[2], points[6], points[5], color)
    sdf_obstacle_gizmo_quad(points[3], points[7], points[6], points[2], color)
    sdf_obstacle_gizmo_quad(points[0], points[1], points[5], points[4], color)
}

sdf_obstacle_gizmo_cube :: proc(center, axis: flight.Vec3, size: f32, color: canvas2d.Color) {
    if size <= 0 do return
    direction := linalg.normalize0(axis)
    if !(linalg.dot(direction, direction) > .0001) do return
    sdf_obstacle_gizmo_box_between(
        center - direction * (size * .5),
        center + direction * (size * .5),
        direction,
        size,
        size,
        color,
    )
}

sdf_obstacle_gizmo_arrow :: proc(origin: flight.Vec3, axis: SDF_Obstacle_Axis, size: f32, color: canvas2d.Color) {
    direction := sdf_obstacle_axis_vector(axis)
    side_a := axis == .X ? flight.Vec3{0, 1, 0} : flight.Vec3{1, 0, 0}
    side_b := linalg.cross(direction, side_a)
    base_center := origin + direction * size * .82
    radius := size * .10
    tip := origin + direction * size
    corners := [4]flight.Vec3{
        base_center + side_a * radius + side_b * radius,
        base_center - side_a * radius + side_b * radius,
        base_center - side_a * radius - side_b * radius,
        base_center + side_a * radius - side_b * radius,
    }
    for index in 0 ..< len(corners) {
        next := (index + 1) % len(corners)
        sdf_obstacle_gizmo_triangle(tip, corners[index], corners[next], color)
    }
}

sdf_obstacle_rotation_ring :: proc(camera: Perspective_Camera, obstacle: SDF_Torus_Obstacle, axis: SDF_Obstacle_Axis, radius: f32, width, height: i32, color: canvas2d.Color) {
    local_axis := sdf_obstacle_axis_vector(axis)
    local_u := math.abs(local_axis.y) < .9 ? linalg.normalize0(linalg.cross(local_axis, flight.Vec3{0, 1, 0})) : flight.Vec3{1, 0, 0}
    local_v := linalg.cross(local_axis, local_u)
    rotation := flight.normalize_orientation(obstacle.rotation)
    previous := obstacle.position + linalg.mul(rotation, local_u * radius)
    stroke := sdf_obstacle_gizmo_stroke_size(camera, obstacle.position, width, height)
    if stroke <= 0 do return
    for segment in 1 ..< SDF_OBSTACLE_ROTATION_RING_SEGMENTS + 1 {
        angle := f32(segment) * 2 * math.PI / f32(SDF_OBSTACLE_ROTATION_RING_SEGMENTS)
        point := obstacle.position + linalg.mul(rotation, (local_u * math.cos(angle) + local_v * math.sin(angle)) * radius)
        previous_projected := project_3d(camera, previous, width, height)
        point_projected := project_3d(camera, point, width, height)
        if previous_projected.visible && point_projected.visible do sdf_obstacle_gizmo_box_between(
            previous,
            point,
            linalg.mul(rotation, local_axis),
            stroke,
            stroke,
            color,
        )
        previous = point
    }
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
    selected := sdf_obstacle_selected_ptr(editor)
    if editor.in_map || editor.authoring_tool != .Obstacles || selected == nil do return
    world_width, world_height := canvas2d.GetWorldRenderSize()
    focal_length := editor.vehicle_showcase_scene ? VEHICLE_SHOWCASE_FOCAL_LENGTH : f32(1.35)
    camera := perspective_camera(editor.camera_pose, focal_length)
    size := sdf_obstacle_gizmo_size(camera, selected.position, world_width, world_height)
    if size <= 0 do return
    interaction := editor.sdf_obstacle_interaction
    ring_radius := sdf_obstacle_rotation_ring_radius(camera, selected.position, world_width, world_height)
    axes := [3]SDF_Obstacle_Axis{.X, .Y, .Z}
    for axis in axes do sdf_obstacle_rotation_ring(
        camera,
        selected^,
        axis,
        ring_radius,
        world_width,
        world_height,
        sdf_obstacle_gizmo_axis_render_color(interaction.gizmo_mode, interaction.constrained_axis, axis),
    )
    if interaction.gizmo_mode == .Rotate {
        if sdf_obstacle_gizmo_center_active(interaction.gizmo_mode, interaction.constrained_axis) do world_box(selected.position, {size * .16, size * .16, size * .16}, SDF_OBSTACLE_GIZMO_ACTIVE_COLOR)
        return
    }
    scale_radius := sdf_obstacle_scale_handle_radius(camera, selected.position, world_width, world_height)
    scale_size := sdf_obstacle_scale_handle_size(camera, selected.position, world_width, world_height)
    rotation := flight.normalize_orientation(selected.rotation)
    for axis in axes {
        world_axis := linalg.mul(rotation, sdf_obstacle_axis_vector(axis))
        color := sdf_obstacle_scale_handle_color(interaction.gizmo_mode, interaction.constrained_axis, axis)
        sdf_obstacle_gizmo_cube(selected.position + world_axis * scale_radius, world_axis, scale_size, color)
    }
    if interaction.gizmo_mode == .Scale {
        if interaction.constrained_axis == .None do sdf_obstacle_gizmo_cube(selected.position, {0, 1, 0}, size * .18, SDF_OBSTACLE_GIZMO_ACTIVE_COLOR)
        return
    }
    shaft_radius := sdf_obstacle_gizmo_stroke_size(camera, selected.position, world_width, world_height)
    for axis in axes {
        direction := sdf_obstacle_axis_vector(axis)
        color := sdf_obstacle_gizmo_axis_render_color(interaction.gizmo_mode, interaction.constrained_axis, axis)
        sdf_obstacle_gizmo_box_between(
            selected.position + direction * (size * .05),
            selected.position + direction * (size * .95),
            direction,
            shaft_radius,
            shaft_radius,
            color,
        )
        sdf_obstacle_gizmo_arrow(selected.position, axis, size, color)
    }
    if sdf_obstacle_gizmo_center_active(interaction.gizmo_mode, interaction.constrained_axis) do world_box(selected.position, {size * .18, size * .18, size * .18}, SDF_OBSTACLE_GIZMO_ACTIVE_COLOR)
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
