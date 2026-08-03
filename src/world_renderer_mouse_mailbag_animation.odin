package main
import "core:math"

import circulation "../packages/circulation"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import gltf "zelda_engine:gltf"

mouse_mailbag_body_surface_local :: proc(
    skeleton: ^[5]Mouse_Bone_Pose,
    local_z, angle: f32,
) -> (
    point: third_person.Vec3,
    hit: bool,
) {
    if skeleton == nil do return
    profile := MOUSE_BODY_PROFILE
    if local_z < profile.ring_z[0] || local_z > profile.ring_z[MOUSE_BODY_RING_COUNT - 1] do return

    lower := 0
    for index in 0 ..< MOUSE_BODY_RING_COUNT - 1 {
        if local_z >= profile.ring_z[index] && local_z <= profile.ring_z[index + 1] {
            lower = index
            break
        }
    }
    upper := min(lower + 1, MOUSE_BODY_RING_COUNT - 1)
    span := max(profile.ring_z[upper] - profile.ring_z[lower], f32(.0001))
    amount := clamp((local_z - profile.ring_z[lower]) / span, 0, 1)
    center_y := profile.center_y[lower] + (profile.center_y[upper] - profile.center_y[lower]) * amount
    body_radius_x := profile.radius_x[lower] + (profile.radius_x[upper] - profile.radius_x[lower]) * amount
    body_radius_y := profile.radius_y[lower] + (profile.radius_y[upper] - profile.radius_y[lower]) * amount
    bind_point := third_person.Vec3 {
        math.cos(angle) * body_radius_x,
        center_y + math.sin(angle) * body_radius_y,
        local_z,
    }
    return mouse_body_profile_skin(bind_point, skeleton, lower, upper, amount), true
}

mouse_mailbag_body_surface_sample :: proc(
    origin: third_person.Vec3,
    rotation: f32,
    skeleton: ^[5]Mouse_Bone_Pose,
    local_z, angle, clearance: f32,
) -> (
    point, normal: third_person.Vec3,
    hit: bool,
) {
    local, local_hit := mouse_mailbag_body_surface_local(skeleton, local_z, angle)
    if !local_hit do return
    angle_before, _ := mouse_mailbag_body_surface_local(skeleton, local_z, angle - .025)
    angle_after, _ := mouse_mailbag_body_surface_local(skeleton, local_z, angle + .025)
    z_before, _ := mouse_mailbag_body_surface_local(skeleton, max(local_z - .010, f32(-.859)), angle)
    z_after, _ := mouse_mailbag_body_surface_local(skeleton, min(local_z + .010, f32(.579)), angle)
    local_normal := linalg.normalize0(linalg.cross(angle_after - angle_before, z_after - z_before))
    if linalg.length(local_normal) <= .0001 {
        local_normal = {math.cos(angle), math.sin(angle), 0}
    }
    local += local_normal * clearance
    point = mouse_mailbag_world_point(origin, rotation, local)
    normal = {
        local_normal.x * math.cos(rotation) - local_normal.z * math.sin(rotation),
        local_normal.y,
        local_normal.x * math.sin(rotation) + local_normal.z * math.cos(rotation),
    }
    return point, normal, true
}

world_mouse_mailbag_surface_ribbon :: proc(
    points: []third_person.Vec3,
    normals: []third_person.Vec3,
    half_width: f32,
    color: canvas2d.Color,
) {
    MAX_SAMPLES :: 32
    if len(points) < 2 || len(normals) != len(points) || len(points) > MAX_SAMPLES do return
    left, right: [MAX_SAMPLES]third_person.Vec3
    previous_width_axis: third_person.Vec3
    for index in 0 ..< len(points) {
        previous := max(index - 1, 0)
        next := min(index + 1, len(points) - 1)
        tangent := linalg.normalize0(points[next] - points[previous])
        width_axis: third_person.Vec3
        if index == 0 {
            width_axis = linalg.normalize0(linalg.cross(normals[index], tangent))
        } else {
            // Parallel-transport the previous width direction onto the new
            // tangent plane. This preserves frame continuity when the torso
            // bends far enough for independently computed cross products to
            // reverse sign.
            transported := previous_width_axis - tangent * linalg.dot(previous_width_axis, tangent)
            width_axis = linalg.normalize0(transported)
            if linalg.length(width_axis) <= .0001 {
                width_axis = linalg.normalize0(linalg.cross(normals[index], tangent))
            }
            reference := linalg.normalize0(linalg.cross(normals[index], tangent))
            if linalg.dot(width_axis, reference) < 0 do width_axis = -width_axis
        }
        if linalg.length(width_axis) <= .0001 do width_axis = {1, 0, 0}
        previous_width_axis = width_axis
        left[index] = points[index] - width_axis * half_width
        right[index] = points[index] + width_axis * half_width
    }
    for index in 0 ..< len(points) - 1 {
        world_quad(left[index], right[index], right[index + 1], left[index + 1], color)
        world_quad(right[index], left[index], left[index + 1], right[index + 1], color)
    }
}

mouse_mailbag_imported_point :: proc(
    editor: ^Editor,
    anchor: third_person.Vec3,
    rotation: f32,
    vertex: gltf.Vec3,
) -> third_person.Vec3 {
    mesh := &editor.mailbag_pouch_asset.mesh
    MODEL_SCALE :: f32(6.0)
    // The rebuilt game-ready mesh has a shared physical base; retain only a
    // tiny inset so its lower bevel settles into the leather saddle.
    CANVAS_BASE_ABOVE_MIN :: f32(.029)
    center_x := (mesh.min.x + mesh.max.x) * .5
    center_z := (mesh.min.z + mesh.max.z) * .5
    local := third_person.Vec3 {
        (vertex.x - center_x) * MODEL_SCALE,
        (vertex.y - (mesh.min.y + CANVAS_BASE_ABOVE_MIN)) * MODEL_SCALE,
        -(vertex.z - center_z) * MODEL_SCALE,
    }
    roll_cosine, roll_sine := math.cos(editor.mouse_mailbag_roll_lag), math.sin(editor.mouse_mailbag_roll_lag)
    rolled_x := local.x * roll_cosine - local.y * roll_sine
    rolled_y := local.x * roll_sine + local.y * roll_cosine
    yaw_cosine, yaw_sine := math.cos(editor.mouse_mailbag_yaw_lag), math.sin(editor.mouse_mailbag_yaw_lag)
    yawed_x := rolled_x * yaw_cosine - local.z * yaw_sine
    yawed_z := rolled_x * yaw_sine + local.z * yaw_cosine
    world_x, world_z := world_rotate_xz(anchor.x, anchor.z, yawed_x, yawed_z, rotation)
    return {world_x, anchor.y + rolled_y + editor.mouse_mailbag_vertical_lag, world_z}
}

world_mouse_mailbag_imported_pouch :: proc(
    editor: ^Editor,
    origin: third_person.Vec3,
    rotation: f32,
    skeleton: ^[5]Mouse_Bone_Pose,
) {
    if editor == nil || skeleton == nil || !editor.mailbag_pouch_asset.ready do return
    asset := &editor.mailbag_pouch_asset
    anchor, _, hit := mouse_mailbag_body_surface_sample(
        origin,
        rotation,
        skeleton,
        MOUSE_POSTAL_HARNESS.rear_loop_z,
        math.PI / 2,
        MOUSE_POSTAL_HARNESS.saddle_clearance + .018,
    )
    if !hit do return
    mesh := &asset.mesh
    for primitive, primitive_index in mesh.primitives {
        color := world_gltf_material_color({255, 255, 255, 255}, primitive.base_color, 255)
        metallic: f32
        roughness: f32 = .86
        if primitive_index < len(mesh.metallic_factors) do metallic = mesh.metallic_factors[primitive_index]
        if primitive_index < len(mesh.roughness_factors) do roughness = mesh.roughness_factors[primitive_index]
        end := min(primitive.first + primitive.count, len(mesh.indices))
        for index := primitive.first; index + 2 < end; index += 3 {
            ia, ib, ic := mesh.indices[index], mesh.indices[index + 1], mesh.indices[index + 2]
            if ia >= u32(len(mesh.vertices)) || ib >= u32(len(mesh.vertices)) || ic >= u32(len(mesh.vertices)) do continue
            a := mouse_mailbag_imported_point(editor, anchor, rotation, mesh.vertices[ia])
            // The Blender asset's longitudinal axis is mirrored so its flap
            // opening faces the mouse's head. Swap B/C with that reflection to
            // preserve outward triangle winding.
            b := mouse_mailbag_imported_point(editor, anchor, rotation, mesh.vertices[ic])
            c := mouse_mailbag_imported_point(editor, anchor, rotation, mesh.vertices[ib])
            normal := linalg.normalize0(linalg.cross(b - a, c - a))
            append(
                &world_renderer.vertices,
                world_greek_asset_vertex(a, color, normal, metallic, roughness),
                world_greek_asset_vertex(b, color, normal, metallic, roughness),
                world_greek_asset_vertex(c, color, normal, metallic, roughness),
            )
        }
    }
}

world_mouse_mailbag :: proc(editor: ^Editor, origin: third_person.Vec3, rotation: f32, skeleton: ^[5]Mouse_Bone_Pose) {
    if editor == nil || skeleton == nil || !editor.mailbag_pouch_asset.ready do return
    canvas_dark := canvas2d.Color{91, 57, 31, 255}
    leather := canvas2d.Color{67, 39, 27, 255}
    brass := canvas2d.Color{176, 126, 51, 255}
    harness_edge := canvas2d.Color{126, 79, 42, 255}
    harness_design := MOUSE_POSTAL_HARNESS
    harness_clearance := harness_design.fur_clearance
    saddle_clearance := harness_design.saddle_clearance

    // A longitudinal quad grid follows the same dorsal skin surface as the
    // mouse. The pouch adds only restrained local lag around its central
    // anchor; the contact harness below never inherits this offset.
    ROWS :: 9
    COLUMNS :: 5
    row_z := [ROWS]f32{-.62, -.56, -.49, -.42, -.35, -.28, -.21, -.15, -.10}
    column_x := [COLUMNS]f32{-.25, -.13, 0, .13, .25}
    posed: [ROWS][COLUMNS]third_person.Vec3
    for row in 0 ..< ROWS {
        for column in 0 ..< COLUMNS {
            x := column_x[column]
            z := row_z[row]
            surface_y, _, hit := mouse_body_surface_height(skeleton, x, 1.2, z)
            if !hit do surface_y = .64
            // Keep a genuine air-filled pouch volume above the fitted saddle.
            // Previously the crown began almost on the fur and disappeared
            // into the torso anywhere the analytic body surface curved faster
            // than this coarse grid.
            lateral_fullness := 1 - math.abs(x) / .25
            longitudinal_fullness := math.sin(f32(row) / f32(ROWS - 1) * math.PI)
            crown := saddle_clearance + .034 + lateral_fullness * .036 + longitudinal_fullness * .014
            local := third_person.Vec3{x, surface_y + crown, z}
            pivot_z := f32(-.28)
            local.x += editor.mouse_mailbag_yaw_lag * (z - pivot_z)
            local.y += editor.mouse_mailbag_vertical_lag + editor.mouse_mailbag_roll_lag * x
            posed[row][column] = mouse_mailbag_world_point(origin, rotation, local)
        }
    }
    world_mouse_mailbag_imported_pouch(editor, origin, rotation, skeleton)

    // Four named, body-fitted anchors form the leather saddle beneath the
    // canvas pouch. Harness pieces attach here instead of targeting arbitrary
    // pouch-grid vertices.
    saddle_front_left, saddle_front_left_normal, _ := mouse_mailbag_body_surface_sample(
        origin,
        rotation,
        skeleton,
        -.105,
        math.PI - .60,
        saddle_clearance,
    )
    saddle_front_right, saddle_front_right_normal, _ := mouse_mailbag_body_surface_sample(
        origin,
        rotation,
        skeleton,
        -.105,
        .60,
        saddle_clearance,
    )
    saddle_rear_left, saddle_rear_left_normal, _ := mouse_mailbag_body_surface_sample(
        origin,
        rotation,
        skeleton,
        harness_design.rear_loop_z,
        math.PI - .72,
        saddle_clearance,
    )
    saddle_rear_right, saddle_rear_right_normal, _ := mouse_mailbag_body_surface_sample(
        origin,
        rotation,
        skeleton,
        harness_design.rear_loop_z,
        .72,
        saddle_clearance,
    )
    world_quad(saddle_rear_left, saddle_front_left, saddle_front_right, saddle_rear_right, canvas_dark)
    world_quad(saddle_front_left, saddle_rear_left, saddle_rear_right, saddle_front_right, canvas_dark)

    // The concept's Y harness is authored in body-surface coordinates:
    // longitudinal Z plus an angle around the posed torso ellipse. Both
    // branches terminate at one padded sternum junction, safely behind the
    // throat and foreleg sockets.
    BRANCH_SAMPLES :: MOUSE_HARNESS_BRANCH_SAMPLES
    left_angle := [BRANCH_SAMPLES]f32 {
        math.PI - harness_design.right_branch_angle[0],
        math.PI - harness_design.right_branch_angle[1],
        math.PI - harness_design.right_branch_angle[2],
        math.PI - harness_design.right_branch_angle[3],
        math.PI - harness_design.right_branch_angle[4],
        math.PI - harness_design.right_branch_angle[5],
        math.PI - harness_design.right_branch_angle[6],
        math.PI - harness_design.right_branch_angle[7],
        math.PI - harness_design.right_branch_angle[8],
    }
    left_branch, right_branch: [BRANCH_SAMPLES]third_person.Vec3
    left_normals, right_normals: [BRANCH_SAMPLES]third_person.Vec3
    for index in 0 ..< BRANCH_SAMPLES {
        left_branch[index], left_normals[index], _ = mouse_mailbag_body_surface_sample(
            origin,
            rotation,
            skeleton,
            harness_design.branch_z[index],
            left_angle[index],
            harness_clearance,
        )
        right_branch[index], right_normals[index], _ = mouse_mailbag_body_surface_sample(
            origin,
            rotation,
            skeleton,
            harness_design.branch_z[index],
            harness_design.right_branch_angle[index],
            harness_clearance,
        )
    }
    // The long branches terminate on stable saddle anchors. Separate short
    // tabs below absorb the pouch's secondary displacement.
    left_bag_anchor := posed[ROWS - 1][0]
    right_bag_anchor := posed[ROWS - 1][COLUMNS - 1]
    left_branch[0] = saddle_front_left
    right_branch[0] = saddle_front_right
    left_normals[0] = saddle_front_left_normal
    right_normals[0] = saddle_front_right_normal
    world_mouse_mailbag_surface_ribbon(
        left_branch[:],
        left_normals[:],
        harness_design.strap_edge_half_width,
        harness_edge,
    )
    world_mouse_mailbag_surface_ribbon(left_branch[:], left_normals[:], harness_design.strap_half_width, leather)
    world_mouse_mailbag_surface_ribbon(
        right_branch[:],
        right_normals[:],
        harness_design.strap_edge_half_width,
        harness_edge,
    )
    world_mouse_mailbag_surface_ribbon(right_branch[:], right_normals[:], harness_design.strap_half_width, leather)

    // Short flexible tabs carry pouch inertia into brass rings on the stable
    // saddle. The long shoulder branches remain body-fitted and cannot kink.
    left_tab := [3]third_person.Vec3 {
        left_bag_anchor,
        (left_bag_anchor + saddle_front_left) * .5 + saddle_front_left_normal * .012,
        saddle_front_left,
    }
    right_tab := [3]third_person.Vec3 {
        right_bag_anchor,
        (right_bag_anchor + saddle_front_right) * .5 + saddle_front_right_normal * .012,
        saddle_front_right,
    }
    left_tab_normals := [3]third_person.Vec3 {
        saddle_front_left_normal,
        saddle_front_left_normal,
        saddle_front_left_normal,
    }
    right_tab_normals := [3]third_person.Vec3 {
        saddle_front_right_normal,
        saddle_front_right_normal,
        saddle_front_right_normal,
    }
    world_mouse_mailbag_surface_ribbon(left_tab[:], left_tab_normals[:], .020, leather)
    world_mouse_mailbag_surface_ribbon(right_tab[:], right_tab_normals[:], .020, leather)
    world_box_rotated(saddle_front_left + saddle_front_left_normal * .010, {.026, .020, .024}, rotation, brass)
    world_box_rotated(saddle_front_right + saddle_front_right_normal * .010, {.026, .020, .024}, rotation, brass)

    // A shaped surface patch replaces the former yaw-only box, keeping the
    // sternum pad flush to the lower chest in every pose.
    sternum_outer: [4]third_person.Vec3
    sternum_outer[0], _, _ = mouse_mailbag_body_surface_sample(
        origin,
        rotation,
        skeleton,
        .075,
        -1.86,
        harness_clearance + .006,
    )
    sternum_outer[1], _, _ = mouse_mailbag_body_surface_sample(
        origin,
        rotation,
        skeleton,
        .075,
        -1.28,
        harness_clearance + .006,
    )
    sternum_outer[2], _, _ = mouse_mailbag_body_surface_sample(
        origin,
        rotation,
        skeleton,
        .145,
        -1.34,
        harness_clearance + .006,
    )
    sternum_outer[3], _, _ = mouse_mailbag_body_surface_sample(
        origin,
        rotation,
        skeleton,
        .145,
        -1.80,
        harness_clearance + .006,
    )
    world_quad(sternum_outer[0], sternum_outer[1], sternum_outer[2], sternum_outer[3], harness_edge)
    world_quad(sternum_outer[1], sternum_outer[0], sternum_outer[3], sternum_outer[2], harness_edge)

    // The rear stabilizer is a closed circumferential loop sampled from the
    // same posed ellipse as the hull, rather than an upper/lower height jump.
    GIRTH_SAMPLES :: 17
    girth, girth_normals: [GIRTH_SAMPLES]third_person.Vec3
    for index in 0 ..< GIRTH_SAMPLES {
        angle := math.PI / 2 + f32(index) / f32(GIRTH_SAMPLES - 1) * math.PI * 2
        girth[index], girth_normals[index], _ = mouse_mailbag_body_surface_sample(
            origin,
            rotation,
            skeleton,
            harness_design.rear_loop_z,
            angle,
            harness_clearance,
        )
    }
    world_mouse_mailbag_surface_ribbon(girth[:], girth_normals[:], harness_design.strap_edge_half_width, harness_edge)
    world_mouse_mailbag_surface_ribbon(girth[:], girth_normals[:], harness_design.strap_half_width, leather)

    left_rear_tab := [3]third_person.Vec3 {
        posed[1][0],
        (posed[1][0] + saddle_rear_left) * .5 + saddle_rear_left_normal * .010,
        saddle_rear_left,
    }
    right_rear_tab := [3]third_person.Vec3 {
        posed[1][COLUMNS - 1],
        (posed[1][COLUMNS - 1] + saddle_rear_right) * .5 + saddle_rear_right_normal * .010,
        saddle_rear_right,
    }
    left_rear_normals := [3]third_person.Vec3 {
        saddle_rear_left_normal,
        saddle_rear_left_normal,
        saddle_rear_left_normal,
    }
    right_rear_normals := [3]third_person.Vec3 {
        saddle_rear_right_normal,
        saddle_rear_right_normal,
        saddle_rear_right_normal,
    }
    world_mouse_mailbag_surface_ribbon(left_rear_tab[:], left_rear_normals[:], .020, leather)
    world_mouse_mailbag_surface_ribbon(right_rear_tab[:], right_rear_normals[:], .020, leather)

    // Mouse-scale hardware and the urgent-letter pocket are deliberately
    // simple, stable accents on top of the deforming panel structure.
    buckle_center := (left_branch[3] + left_branch[4]) * .5
    world_box_rotated(buckle_center, {.020, .024, .028}, rotation, brass)
    buckle_center = (right_branch[3] + right_branch[4]) * .5
    world_box_rotated(buckle_center, {.020, .024, .028}, rotation, brass)
}

@(no_instrumentation)
mouse_ear_world_point :: #force_inline proc(
    origin, center: third_person.Vec3,
    rotation, yaw, roll, x, y, z: f32,
) -> third_person.Vec3 {
    roll_cosine, roll_sine := math.cos(roll), math.sin(roll)
    rolled_x := x * roll_cosine - y * roll_sine
    rolled_y := x * roll_sine + y * roll_cosine
    cosine, sine := math.cos(yaw), math.sin(yaw)
    local_x := center.x + rolled_x * cosine + z * sine
    local_z := center.z - rolled_x * sine + z * cosine - rolled_y * .20
    world_x, world_z := world_rotate_xz(origin.x, origin.z, local_x, local_z, rotation)
    return {world_x, origin.y + center.y + rolled_y, world_z}
}

world_mouse_ear :: proc(
    origin: third_person.Vec3,
    rotation: f32,
    center: third_person.Vec3,
    side, twitch, yaw_offset, roll: f32,
    rim_color, inner_color: canvas2d.Color,
) {
    SEGMENTS :: 16
    // Mouse pinnae face laterally.  A shallow yaw made them disappear into
    // edge-on slivers in the gameplay side view; this angle preserves their
    // broad oval silhouette while still separating the bilateral pair.
    yaw := side * (1.02 + twitch * 5) + yaw_offset
    outer_back, outer_front, inner_rim: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        cosine, sine := math.cos(angle), math.sin(angle)
        root_taper := .70 + .30 * clamp((sine + .55) / 1.55, 0, 1)
        outer_x := cosine * .101 * root_taper
        outer_y := sine * .108
        inner_x := cosine * .069 * root_taper
        inner_y := .006 + sine * .073
        outer_back[segment] = mouse_ear_world_point(origin, center, rotation, yaw, roll, outer_x, outer_y, -.034)
        outer_front[segment] = mouse_ear_world_point(origin, center, rotation, yaw, roll, outer_x, outer_y, .034)
        inner_rim[segment] = mouse_ear_world_point(origin, center, rotation, yaw, roll, inner_x, inner_y, .036)
    }

    back_center := mouse_ear_world_point(origin, center, rotation, yaw, roll, 0, 0, -.034)
    // Recessing the pink center behind its inner rim gives the pinna a shallow
    // bowl instead of reading as a sticker laid over a flat disc.
    cup_center := mouse_ear_world_point(origin, center, rotation, yaw, roll, 0, .008, .014)
    // Thin mouse ears transmit some of their pink tone even from behind. This
    // keeps the far pinna recognizable instead of reducing it to a dark fur
    // bump when its cup faces away from the camera.
    back_color := color_lerp(rim_color, inner_color, .34)
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        // The back cap faces away from the pink cup. Wind it outward so it
        // survives normal back-face culling and occludes the inner surfaces
        // when the far pinna is viewed from behind.
        world_triangle(back_center, outer_back[next], outer_back[segment], back_color)
        world_quad(outer_back[segment], outer_back[next], outer_front[next], outer_front[segment], rim_color)
        world_quad(outer_front[segment], outer_front[next], inner_rim[next], inner_rim[segment], rim_color)
        world_triangle(cup_center, inner_rim[segment], inner_rim[next], inner_color)
    }
}

player_animation_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    mouse_body_softness_update(editor, delta_seconds)
    if delta_seconds <= 0 do return
    animation := &editor.tweak.player_animation
    horizontal_speed := f32(
        math.sqrt(
            f64(
                editor.player.velocity.x * editor.player.velocity.x +
                editor.player.velocity.z * editor.player.velocity.z,
            ),
        ),
    )
    speed_acceleration := clamp(
        (horizontal_speed - editor.player_animation_previous_speed) / max(delta_seconds, f32(.001)),
        -30,
        30,
    )
    editor.player_animation_previous_speed = horizontal_speed
    scurry_target :=
        editor.player.running && editor.player.grounded && horizontal_speed > max(animation.walk_full_speed * .72, f32(.1)) ? f32(1) : f32(0)
    if editor.player.boost_seconds > 0 && editor.player.grounded do scurry_target = 1
    editor.player_scurry_weight = player_animation_approach(
        editor.player_scurry_weight,
        scurry_target,
        animation.locomotion_blend_rate * .8,
        delta_seconds,
    )
    scurry_lean_target :=
        editor.player_scurry_weight *
        (animation.scurry_lean_radians + speed_acceleration * animation.scurry_acceleration_lean)
    compression_impulse := max(math.sin(editor.player_stride_phase), f32(0))
    scurry_compression_target := editor.player_scurry_weight * compression_impulse * animation.scurry_compression
    player_animation_spring(
        &editor.player_scurry_lean,
        &editor.player_scurry_lean_velocity,
        scurry_lean_target,
        animation.scurry_spring_stiffness,
        animation.scurry_spring_damping,
        delta_seconds,
    )
    player_animation_spring(
        &editor.player_scurry_compression,
        &editor.player_scurry_compression_velocity,
        scurry_compression_target,
        animation.scurry_spring_stiffness * 1.25,
        animation.scurry_spring_damping,
        delta_seconds,
    )
    gait_target := clamp(horizontal_speed / max(animation.walk_full_speed, f32(.1)), 0, 1)
    airborne_target := editor.player.grounded ? f32(0) : f32(1)
    vertical_target := f32(0)
    if !editor.player.grounded {
        vertical_target = clamp(editor.player.velocity.y / max(animation.vertical_full_speed, f32(.1)), -1, 1)
    }
    editor.player_gait_weight = player_animation_approach(
        editor.player_gait_weight,
        gait_target,
        animation.locomotion_blend_rate,
        delta_seconds,
    )
    editor.player_airborne_weight = player_animation_approach(
        editor.player_airborne_weight,
        airborne_target,
        animation.airborne_blend_rate,
        delta_seconds,
    )
    editor.player_vertical_pose = player_animation_approach(
        editor.player_vertical_pose,
        vertical_target,
        animation.vertical_blend_rate,
        delta_seconds,
    )
    editor.player_turn_pose = player_animation_approach(
        editor.player_turn_pose,
        editor.player.turn_amount,
        animation.turn_blend_rate,
        delta_seconds,
    )
    editor.player_brake_pose = player_animation_approach(
        editor.player_brake_pose,
        editor.player.brake_amount,
        animation.brake_blend_rate,
        delta_seconds,
    )
    if editor.player.grounded && horizontal_speed < .08 {
        editor.player_posted_idle_seconds += delta_seconds
    } else {
        editor.player_posted_idle_seconds = 0
    }
    posted_target := editor.player_posted_idle_seconds >= 2.75 ? f32(1) : f32(0)
    editor.player_posted_weight = player_animation_approach(
        editor.player_posted_weight,
        posted_target,
        2.6,
        delta_seconds,
    )
    if editor.player.grounded {
        gait := mouse_gait_weights(animation, horizontal_speed, editor.player_airborne_weight)
        stride_radians_per_meter :=
            animation.stride_radians_per_meter * gait.walk +
            animation.trot_stride_radians_per_meter * gait.trot +
            animation.bound_stride_radians_per_meter * gait.bound
        editor.player_stride_phase += horizontal_speed * delta_seconds * max(stride_radians_per_meter, f32(.1))
        for editor.player_stride_phase >= math.PI * 2 do editor.player_stride_phase -= math.PI * 2
    }
}

mouse_surface_height :: proc(editor: ^Editor, x, z: f32) -> f32 {
    height := terrain.sample_surface_height(&editor.project, 0, x, z)
    plan := editor_circulation_plan(editor)
    if !world_renderer.pavement_query_graph_valid ||
       world_renderer.pavement_query_revision != editor.project.revision {
        if !world_renderer.pavement_query_graph_valid ||
           world_renderer.pavement_query_graph != editor.project.road_graph {
            roads.pavement_query_build(&editor.project.road_graph, &world_renderer.pavement_query)
            world_renderer.pavement_query_graph = editor.project.road_graph
            world_renderer.pavement_query_graph_valid = true
        }
        world_renderer.pavement_query_revision = editor.project.revision
    }
    surface := circulation.surface_at_cached(
        &editor.project.road_graph,
        plan,
        &world_renderer.pavement_query,
        {x, height, z},
    )
    if surface.on_surface {
        road_height := height
        if surface.from_authored &&
           surface.edge_index >= 0 &&
           surface.edge_index < editor.project.road_graph.edge_count {
            edge := editor.project.road_graph.edges[surface.edge_index]
            // Ordinary roads are rendered as terrain overlays. Their stored
            // spline Y can be stale (especially on generated island links),
            // so it must not create an invisible support plane above the
            // visible road. Designed profiles and bridge decks are the two
            // cases where the renderer deliberately departs from terrain.
            if edge.engineering_designed && edge.authored_profile {
                road_height = surface.height
            }
            if deck_height, bridge := road_bridge_deck_height(editor, surface.edge_index, surface.amount); bridge {
                road_height = deck_height
            }
        }
        height = max(height + .12, road_height + .12)
    }
    return height
}
