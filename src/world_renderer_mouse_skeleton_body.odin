package main
import "core:math"
import "core:testing"

import third_person "../packages/third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

// Pose channels are authored as absolute mouse-local pivots. Keep those
// pivots connected after all locomotion and emote contributions have been
// composed: an invalid or over-large channel offset must not tear a child
// joint away from the rest of the rig and fling its weighted vertices out of
// the body. Compression remains unconstrained so crouches and squash poses
// retain their authored silhouette.
mouse_skeleton_keep_joints_connected :: proc(skeleton: ^[5]Mouse_Bone_Pose) {
    if skeleton == nil do return
    authored := skeleton^
    for child_index in 1 ..< len(skeleton) {
        child := &skeleton[child_index]
        parent_index := int(child.parent)
        if parent_index < 0 || parent_index >= child_index do continue
        parent := &skeleton[parent_index]
        authored_child := authored[child_index]
        authored_parent := authored[parent_index]
        bind_offset := authored_child.bind_position - authored_parent.bind_position
        pitch_cosine, pitch_sine := math.cos(authored_parent.pitch), math.sin(authored_parent.pitch)
        pitched_y := bind_offset.y * pitch_cosine - bind_offset.z * pitch_sine
        pitched_z := bind_offset.y * pitch_sine + bind_offset.z * pitch_cosine
        yaw_cosine, yaw_sine := math.cos(authored_parent.yaw), math.sin(authored_parent.yaw)
        yawed_x := bind_offset.x * yaw_cosine + pitched_z * yaw_sine
        yawed_z := -bind_offset.x * yaw_sine + pitched_z * yaw_cosine
        roll_cosine, roll_sine := math.cos(authored_parent.roll), math.sin(authored_parent.roll)
        inherited_bind_offset := third_person.Vec3 {
            yawed_x * roll_cosine - pitched_y * roll_sine,
            yawed_x * roll_sine + pitched_y * roll_cosine,
            yawed_z,
        }
        // Positions are authored in mouse space. Preserve the child's local
        // translation contribution while carrying its bind pivot through the
        // evaluated parent transform.
        child_local_translation :=
            (authored_child.position - authored_child.bind_position) -
            (authored_parent.position - authored_parent.bind_position)
        child.position = parent.position + inherited_bind_offset + child_local_translation
        bind_length := linalg.length(child.bind_position - parent.bind_position)
        posed_offset := child.position - parent.position
        if math.is_nan(posed_offset.x) ||
           math.is_inf(posed_offset.x) ||
           math.is_nan(posed_offset.y) ||
           math.is_inf(posed_offset.y) ||
           math.is_nan(posed_offset.z) ||
           math.is_inf(posed_offset.z) {
            child.position = parent.position + child.bind_position - parent.bind_position
            continue
        }
        posed_length := linalg.length(posed_offset)
        maximum_length := bind_length * 1.4
        if posed_length > maximum_length && posed_length > .0001 {
            child.position = parent.position + posed_offset * (maximum_length / posed_length)
        }
    }
}

when ODIN_TEST {
    @(test)
    mouse_skeleton_keeps_escaped_child_joint_connected :: proc(t: ^testing.T) {
        skeleton := [5]Mouse_Bone_Pose {
            {parent = -1, bind_position = {0, 0, 0}, position = {1, 2, 3}},
            {parent = 0, bind_position = {0, 0, .2}, position = {1, 2, 30}},
            {parent = 1, bind_position = {0, 0, .4}, position = {1, 2, 30.2}},
            {},
            {},
        }
        mouse_skeleton_keep_joints_connected(&skeleton)
        maximum := f32(.2 * 1.4)
        testing.expect(t, linalg.length(skeleton[1].position - skeleton[0].position) <= maximum + .0001)
        testing.expect(t, linalg.length(skeleton[2].position - skeleton[1].position) <= maximum + .0001)
    }

    @(test)
    mouse_skeleton_preserves_connected_authored_joint :: proc(t: ^testing.T) {
        skeleton := [5]Mouse_Bone_Pose {
            {parent = -1, bind_position = {0, 0, 0}, position = {1, 2, 3}},
            {parent = 0, bind_position = {0, 0, .2}, position = {1.05, 2.04, 3.21}},
            {},
            {},
            {},
        }
        authored := skeleton[1].position
        mouse_skeleton_keep_joints_connected(&skeleton)
        testing.expect_value(t, skeleton[1].position, authored)
    }

    @(test)
    mouse_skeleton_child_pivot_inherits_parent_rotation :: proc(t: ^testing.T) {
        skeleton := [5]Mouse_Bone_Pose {
            {parent = -1, roll = math.PI * .5},
            {parent = 0, bind_position = {.2, 0, 0}, position = {.2, 0, 0}},
            {},
            {},
            {},
        }
        mouse_skeleton_keep_joints_connected(&skeleton)
        testing.expect(t, math.abs(skeleton[1].position.x) < .0001)
        testing.expect(t, math.abs(skeleton[1].position.y - .2) < .0001)
    }

    @(test)
    mouse_ground_reach_never_leaves_an_impossible_endpoint :: proc(t: ^testing.T) {
        root := third_person.Vec3{1, 2, 3}
        target := third_person.Vec3{8, 9, 10}
        mouse_clamp_ground_contact_reach(root, &target, .47)
        testing.expect(t, linalg.length(target - root) <= .4701)
    }
}

MOUSE_BODY_RING_COUNT :: 11
MOUSE_BODY_SEGMENT_COUNT :: 12

Mouse_Body_Softness_State :: struct {
    displacement:       [MOUSE_BODY_RING_COUNT][MOUSE_BODY_SEGMENT_COUNT]third_person.Vec3,
    velocity:           [MOUSE_BODY_RING_COUNT][MOUSE_BODY_SEGMENT_COUNT]third_person.Vec3,
    target:             [MOUSE_BODY_RING_COUNT][MOUSE_BODY_SEGMENT_COUNT]third_person.Vec3,
    previous_target:    [MOUSE_BODY_RING_COUNT][MOUSE_BODY_SEGMENT_COUNT]third_person.Vec3,
    placement_revision: u64,
    initialized:        bool,
}

Mouse_Body_Profile :: struct {
    ring_z:         [MOUSE_BODY_RING_COUNT]f32,
    center_y:       [MOUSE_BODY_RING_COUNT]f32,
    radius_x:       [MOUSE_BODY_RING_COUNT]f32,
    radius_y:       [MOUSE_BODY_RING_COUNT]f32,
    primary:        [MOUSE_BODY_RING_COUNT]Mouse_Bone,
    secondary:      [MOUSE_BODY_RING_COUNT]Mouse_Bone,
    primary_weight: [MOUSE_BODY_RING_COUNT]f32,
}

mouse_body_softness_reset :: proc(state: ^Mouse_Body_Softness_State, placement_revision: u64) {
    if state == nil do return
    state^ = {}
    state.placement_revision = placement_revision
    state.initialized = true
}

mouse_body_softness_vec_finite :: #force_inline proc(value: third_person.Vec3) -> bool {
    return(
        !math.is_nan(value.x) &&
        !math.is_inf(value.x) &&
        !math.is_nan(value.y) &&
        !math.is_inf(value.y) &&
        !math.is_nan(value.z) &&
        !math.is_inf(value.z) \
    )
}

mouse_body_softness_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    state := &editor.player_body_softness
    if !state.initialized ||
       state.placement_revision != editor.player_placement_revision ||
       delta_seconds <= 0 ||
       delta_seconds > .25 {
        mouse_body_softness_reset(state, editor.player_placement_revision)
        return
    }

    animation := &editor.tweak.player_animation
    frame_seconds := min(delta_seconds, f32(1.0 / 30.0))
    substeps := max(1, int(math.ceil(f64(frame_seconds / f32(1.0 / 120.0)))))
    step_seconds := frame_seconds / f32(substeps)

    // Compression removes radial area from a ring. Return a restrained share
    // of it over the rest of that ring so a moving thigh or shoulder reads as
    // yielding flesh rather than a dent stamped into a rigid shell.
    resolved_target := state.target
    for ring in 0 ..< MOUSE_BODY_RING_COUNT {
        inward_sum: f32
        for segment in 0 ..< MOUSE_BODY_SEGMENT_COUNT {
            angle := f32(segment) * math.PI * 2 / f32(MOUSE_BODY_SEGMENT_COUNT)
            radial := third_person.Vec3{math.cos(angle), math.sin(angle), 0}
            inward_sum += max(-linalg.dot(resolved_target[ring][segment], radial), f32(0))
        }
        returned := inward_sum / f32(MOUSE_BODY_SEGMENT_COUNT) * animation.body_softness_volume_return
        for segment in 0 ..< MOUSE_BODY_SEGMENT_COUNT {
            angle := f32(segment) * math.PI * 2 / f32(MOUSE_BODY_SEGMENT_COUNT)
            radial := third_person.Vec3{math.cos(angle), math.sin(angle), 0}
            resolved_target[ring][segment] += radial * returned
        }
    }

    for ring in 0 ..< MOUSE_BODY_RING_COUNT {
        for segment in 0 ..< MOUSE_BODY_SEGMENT_COUNT {
            target_delta := resolved_target[ring][segment] - state.previous_target[ring][segment]
            state.velocity[ring][segment] +=
                target_delta * animation.body_softness_inertial_lag / max(frame_seconds, f32(.001))
        }
    }
    for _ in 0 ..< substeps {
        for ring in 0 ..< MOUSE_BODY_RING_COUNT {
            for segment in 0 ..< MOUSE_BODY_SEGMENT_COUNT {
                target := resolved_target[ring][segment]
                acceleration :=
                    (target - state.displacement[ring][segment]) * animation.body_softness_stiffness -
                    state.velocity[ring][segment] * animation.body_softness_damping
                state.velocity[ring][segment] += acceleration * step_seconds
                state.displacement[ring][segment] += state.velocity[ring][segment] * step_seconds
                length := linalg.length(state.displacement[ring][segment])
                if length > animation.body_softness_max_displacement && length > .0001 {
                    state.displacement[ring][segment] *= animation.body_softness_max_displacement / length
                    state.velocity[ring][segment] *= .35
                }
                if !mouse_body_softness_vec_finite(state.displacement[ring][segment]) ||
                   !mouse_body_softness_vec_finite(state.velocity[ring][segment]) {
                    mouse_body_softness_reset(state, editor.player_placement_revision)
                    return
                }
            }
        }
    }
    state.previous_target = resolved_target
    state.target = {}
}

MOUSE_BODY_PROFILE :: Mouse_Body_Profile {
    ring_z         = {-.86, -.76, -.64, -.48, -.28, -.04, .10, .20, .32, .47, .58},
    center_y       = {.35, .35, .38, .43, .47, .52, .59, .68, .64, .61, .62},
    radius_x       = {.008, .15, .25, .30, .30, .255, .205, .20, .17, .095, .025},
    radius_y       = {.010, .18, .28, .34, .35, .28, .21, .185, .125, .070, .022},
    primary        = {.Pelvis, .Pelvis, .Pelvis, .Pelvis, .Spine, .Chest, .Neck, .Head, .Head, .Head, .Head},
    secondary      = {.Spine, .Spine, .Spine, .Spine, .Pelvis, .Spine, .Chest, .Neck, .Neck, .Neck, .Neck},
    primary_weight = {1, .98, .92, .82, .76, .68, .66, .78, .88, .96, 1},
}

MOUSE_HARNESS_BRANCH_SAMPLES :: 9

Mouse_Harness_Design :: struct {
    branch_z:              [MOUSE_HARNESS_BRANCH_SAMPLES]f32,
    right_branch_angle:    [MOUSE_HARNESS_BRANCH_SAMPLES]f32,
    rear_loop_z:           f32,
    fur_clearance:         f32,
    saddle_clearance:      f32,
    strap_half_width:      f32,
    strap_edge_half_width: f32,
}

MOUSE_POSTAL_HARNESS :: Mouse_Harness_Design {
    branch_z              = {-.10, -.055, -.010, .030, .065, .095, .115, .130, .140},
    right_branch_angle    = {.58, .38, .16, -.08, -.34, -.62, -.88, -1.18, -1.50},
    rear_loop_z           = -.34,
    fur_clearance         = .042,
    saddle_clearance      = .042,
    strap_half_width      = .018,
    strap_edge_half_width = .024,
}

Mouse_Vertex_Group :: struct {
    bone:   Mouse_Bone,
    weight: f32,
}

mouse_body_profile_skin :: proc(
    bind_position: third_person.Vec3,
    skeleton: ^[5]Mouse_Bone_Pose,
    lower, upper: int,
    amount: f32,
) -> third_person.Vec3 {
    profile := MOUSE_BODY_PROFILE
    lower_groups := [2]Mouse_Vertex_Group {
        {profile.primary[lower], profile.primary_weight[lower]},
        {profile.secondary[lower], 1 - profile.primary_weight[lower]},
    }
    upper_groups := [2]Mouse_Vertex_Group {
        {profile.primary[upper], profile.primary_weight[upper]},
        {profile.secondary[upper], 1 - profile.primary_weight[upper]},
    }
    lower_point := mouse_skin_vertex({bind_position = bind_position, groups = lower_groups}, skeleton)
    upper_point := mouse_skin_vertex({bind_position = bind_position, groups = upper_groups}, skeleton)
    return lower_point + (upper_point - lower_point) * amount
}

Mouse_Skin_Vertex :: struct {
    bind_position: third_person.Vec3,
    groups:        [2]Mouse_Vertex_Group,
    color:         canvas2d.Color,
}

@(no_instrumentation)
mouse_skin_vertex :: #force_inline proc(
    vertex: Mouse_Skin_Vertex,
    skeleton: ^[5]Mouse_Bone_Pose,
) -> third_person.Vec3 {
    skinned: third_person.Vec3
    weight_sum: f32
    for group in vertex.groups {
        if group.weight <= 0 do continue
        bone := skeleton[int(group.bone)]
        relative := third_person.Vec3 {
            vertex.bind_position.x - bone.bind_position.x,
            vertex.bind_position.y - bone.bind_position.y,
            vertex.bind_position.z - bone.bind_position.z,
        }
        pitch_cosine, pitch_sine := math.cos(bone.pitch), math.sin(bone.pitch)
        pitched_y := relative.y * pitch_cosine - relative.z * pitch_sine
        pitched_z := relative.y * pitch_sine + relative.z * pitch_cosine
        yaw_cosine, yaw_sine := math.cos(bone.yaw), math.sin(bone.yaw)
        yawed_x := relative.x * yaw_cosine + pitched_z * yaw_sine
        yawed_z := -relative.x * yaw_sine + pitched_z * yaw_cosine
        roll_cosine, roll_sine := math.cos(bone.roll), math.sin(bone.roll)
        transformed := third_person.Vec3 {
            bone.position.x + yawed_x * roll_cosine - pitched_y * roll_sine,
            bone.position.y + yawed_x * roll_sine + pitched_y * roll_cosine,
            bone.position.z + yawed_z,
        }
        skinned.x += transformed.x * group.weight
        skinned.y += transformed.y * group.weight
        skinned.z += transformed.z * group.weight
        weight_sum += group.weight
    }
    if weight_sum <= .0001 do return vertex.bind_position
    inverse_weight := 1 / weight_sum
    return {skinned.x * inverse_weight, skinned.y * inverse_weight, skinned.z * inverse_weight}
}

mouse_body_surface_height :: proc(
    skeleton: ^[5]Mouse_Bone_Pose,
    local_x, local_y, local_z: f32,
) -> (
    height: f32,
    push_up, hit: bool,
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
    if body_radius_x <= .001 || math.abs(local_x) >= body_radius_x do return
    normalized_x := clamp(local_x / body_radius_x, -1, 1)
    vertical_radius := body_radius_y * f32(math.sqrt(f64(max(1 - normalized_x * normalized_x, f32(0)))))
    posed_center := mouse_body_profile_skin({local_x, center_y, local_z}, skeleton, lower, upper, amount)
    push_up = local_y >= posed_center.y
    surface_y := center_y + (push_up ? vertical_radius : -vertical_radius)
    posed_surface := mouse_body_profile_skin({local_x, surface_y, local_z}, skeleton, lower, upper, amount)
    return posed_surface.y, push_up, true
}

world_mouse_skinned_hull :: proc(
    origin: third_person.Vec3,
    rotation: f32,
    skeleton: ^[5]Mouse_Bone_Pose,
    fur, fur_dark, fur_light: canvas2d.Color,
    pattern: Mouse_Fur_Pattern,
    breath: f32,
    softness: ^Mouse_Body_Softness_State = nil,
) {
    RINGS :: MOUSE_BODY_RING_COUNT
    SEGMENTS :: MOUSE_BODY_SEGMENT_COUNT
    profile := MOUSE_BODY_PROFILE
    // A mouse's dorsal line is a soft arch over the pelvis and ribs, then
    // descends into the neck.  Keeping the belly locations nearly unchanged
    // while lifting and enlarging these middle rings avoids the flat-backed,
    // rectangular silhouette that the low running pose previously produced.
    // Collapse the first ring almost to a pole, then ease through two
    // intermediate pelvis rings. This closes the rump as a rounded volume
    // instead of exposing the flat fan that used to cap a wide rear ellipse.
    vertices: [RINGS][SEGMENTS]Mouse_Skin_Vertex
    posed: [RINGS][SEGMENTS]third_person.Vec3
    rib_weights := [RINGS]f32{0, 0, .02, .10, .55, 1, .45, 0, 0, 0, 0}
    for ring in 0 ..< RINGS {
        breath_scale := 1 + breath * rib_weights[ring]
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
            cosine, sine := math.cos(angle), math.sin(angle)
            belly_weight := clamp((-sine - .05) * .76, 0, .68)
            if ring >= 6 do belly_weight = max(belly_weight, f32(.48))
            dorsal_weight := clamp((sine - .10) * .30, 0, .27)
            if ring >= 6 do dorsal_weight *= .55
            coat_color := color_lerp(fur, fur_light, belly_weight)
            coat_color = color_lerp(coat_color, fur_dark, dorsal_weight)
            marking := color_lerp(fur_light, {247, 239, 218, 255}, .72)
            switch pattern {
            case .Solid:
            case .Pale_Belly:
                pale_weight := clamp((-sine + .15) * 1.15, 0, .92)
                coat_color = color_lerp(coat_color, marking, pale_weight)
            case .Hooded:
                if ring < 6 {
                    hood_edge := ring == 5 ? clamp((sine + .2) * .7, 0, 1) : f32(1)
                    coat_color = color_lerp(coat_color, marking, hood_edge)
                }
            case .Piebald:
                patch_value := (ring * 7 + segment * 3 + (segment / 3) * 5) % 13
                if patch_value < 5 do coat_color = color_lerp(coat_color, marking, .92)
            case .Dorsal_Stripe:
                // A narrow dark stripe follows the spine and softens toward
                // the flanks, as on striped field mice.
                stripe_center := clamp((sine - .48) * 3.4, 0, 1)
                stripe_taper := ring == 0 || ring >= 8 ? f32(.62) : f32(1)
                coat_color = color_lerp(coat_color, fur_dark, stripe_center * stripe_taper)
            case .Masked:
                // Keep the muzzle pale while wrapping a dark mask around the
                // crown and sides of the head.
                if ring >= 6 && ring < 9 {
                    mask_weight := clamp((sine + .35) * .78, 0, .88)
                    coat_color = color_lerp(coat_color, fur_dark, mask_weight)
                } else if ring == 9 {
                    coat_color = color_lerp(coat_color, marking, .42)
                }
            }
            vertices[ring][segment] = {
                bind_position = {
                    cosine * profile.radius_x[ring] * breath_scale,
                    profile.center_y[ring] + sine * profile.radius_y[ring] * breath_scale,
                    profile.ring_z[ring],
                },
                groups        = {
                    {profile.primary[ring], profile.primary_weight[ring]},
                    {profile.secondary[ring], 1 - profile.primary_weight[ring]},
                },
                color         = coat_color,
            }
            local := mouse_skin_vertex(vertices[ring][segment], skeleton)
            if softness != nil && softness.initialized {
                local += softness.displacement[ring][segment]
            }
            world_x, world_z := world_rotate_xz(origin.x, origin.z, local.x, local.z, rotation)
            posed[ring][segment] = {world_x, origin.y + local.y, world_z}
        }
    }

    normals: [RINGS][SEGMENTS]third_person.Vec3
    for ring in 0 ..< RINGS {
        before_ring := max(ring - 1, 0)
        after_ring := min(ring + 1, RINGS - 1)
        for segment in 0 ..< SEGMENTS {
            before := (segment + SEGMENTS - 1) % SEGMENTS
            after := (segment + 1) % SEGMENTS
            around := posed[ring][after] - posed[ring][before]
            along := posed[after_ring][segment] - posed[before_ring][segment]
            normals[ring][segment] = linalg.normalize0(linalg.cross(around, along))
        }
    }
    emit_triangle :: proc(
        a, b, c: third_person.Vec3,
        normal_a, normal_b, normal_c: third_person.Vec3,
        color_a, color_b, color_c: canvas2d.Color,
    ) {
        output := [3]World_Vertex{world_vertex(a, color_a), world_vertex(b, color_b), world_vertex(c, color_c)}
        input_normals := [3]third_person.Vec3{normal_a, normal_b, normal_c}
        for index in 0 ..< 3 {
            normal := linalg.normalize0(input_normals[index])
            output[index].normal = {normal.x, normal.y, normal.z}
        }
        append(&world_renderer.vertices, ..output[:])
    }
    for ring in 0 ..< RINGS - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            a, b := posed[ring][segment], posed[ring][next]
            c, d := posed[ring + 1][next], posed[ring + 1][segment]
            emit_triangle(
                a,
                b,
                c,
                normals[ring][segment],
                normals[ring][next],
                normals[ring + 1][next],
                vertices[ring][segment].color,
                vertices[ring][next].color,
                vertices[ring + 1][next].color,
            )
            emit_triangle(
                a,
                c,
                d,
                normals[ring][segment],
                normals[ring + 1][next],
                normals[ring + 1][segment],
                vertices[ring][segment].color,
                vertices[ring + 1][next].color,
                vertices[ring + 1][segment].color,
            )
        }
    }

    rear_center_local := mouse_skin_vertex(
        {
            bind_position = {0, profile.center_y[0], profile.ring_z[0]},
            groups = {{.Pelvis, 1}, {.Spine, 0}},
            color = fur,
        },
        skeleton,
    )
    nose_center_local := mouse_skin_vertex(
        {
            bind_position = {0, profile.center_y[RINGS - 1], profile.ring_z[RINGS - 1]},
            groups = {{.Head, 1}, {.Neck, 0}},
            color = fur_light,
        },
        skeleton,
    )
    rear_x, rear_z := world_rotate_xz(origin.x, origin.z, rear_center_local.x, rear_center_local.z, rotation)
    nose_x, nose_z := world_rotate_xz(origin.x, origin.z, nose_center_local.x, nose_center_local.z, rotation)
    rear_center := third_person.Vec3{rear_x, origin.y + rear_center_local.y, rear_z}
    nose_center := third_person.Vec3{nose_x, origin.y + nose_center_local.y, nose_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(rear_center, posed[0][next], posed[0][segment], fur)
        world_triangle(nose_center, posed[RINGS - 1][segment], posed[RINGS - 1][next], fur_light)
    }
}

mouse_body_softness_accumulate_capsule :: proc(
    state: ^Mouse_Body_Softness_State,
    origin: third_person.Vec3,
    rotation: f32,
    world_start, world_end: third_person.Vec3,
    strength, influence_radius: f32,
) {
    if state == nil || !state.initialized || strength <= 0 || influence_radius <= .001 do return
    cosine, sine := math.cos(rotation), math.sin(rotation)
    start_delta, finish_delta := world_start - origin, world_end - origin
    start := third_person.Vec3 {
        start_delta.x * cosine + start_delta.z * sine,
        start_delta.y,
        -start_delta.x * sine + start_delta.z * cosine,
    }
    finish := third_person.Vec3 {
        finish_delta.x * cosine + finish_delta.z * sine,
        finish_delta.y,
        -finish_delta.x * sine + finish_delta.z * cosine,
    }
    axis := finish - start
    axis_length_squared := linalg.dot(axis, axis)
    profile := MOUSE_BODY_PROFILE
    for ring in 0 ..< MOUSE_BODY_RING_COUNT {
        for segment in 0 ..< MOUSE_BODY_SEGMENT_COUNT {
            angle := f32(segment) * math.PI * 2 / f32(MOUSE_BODY_SEGMENT_COUNT)
            radial := third_person.Vec3{math.cos(angle), math.sin(angle), 0}
            surface := third_person.Vec3 {
                radial.x * profile.radius_x[ring],
                profile.center_y[ring] + radial.y * profile.radius_y[ring],
                profile.ring_z[ring],
            }
            amount: f32
            if axis_length_squared > .000001 {
                amount = clamp(linalg.dot(surface - start, axis) / axis_length_squared, 0, 1)
            }
            nearest := start + axis * amount
            distance := linalg.length(surface - nearest)
            influence := clamp(1 - distance / influence_radius, 0, 1)
            influence = influence * influence * (3 - 2 * influence)
            compression := influence * strength * .065
            candidate := radial * -compression
            // Multiple render submissions or overlapping limb capsules must
            // not pump extra energy into the next simulation update.
            existing_inward := max(-linalg.dot(state.target[ring][segment], radial), f32(0))
            if compression > existing_inward {
                state.target[ring][segment] = candidate
            }
        }
    }
}

mouse_body_softness_sample :: proc(
    state: ^Mouse_Body_Softness_State,
    bind_point: third_person.Vec3,
) -> third_person.Vec3 {
    if state == nil || !state.initialized do return {}
    profile := MOUSE_BODY_PROFILE
    best_ring := 0
    best_distance := f32(1e9)
    for ring in 0 ..< MOUSE_BODY_RING_COUNT {
        distance := math.abs(profile.ring_z[ring] - bind_point.z)
        if distance < best_distance {
            best_distance = distance
            best_ring = ring
        }
    }
    normalized_x := bind_point.x / max(profile.radius_x[best_ring], f32(.001))
    normalized_y := (bind_point.y - profile.center_y[best_ring]) / max(profile.radius_y[best_ring], f32(.001))
    angle := math.atan2(normalized_y, normalized_x)
    if angle < 0 do angle += math.PI * 2
    segment := int(math.round(angle / (math.PI * 2) * f32(MOUSE_BODY_SEGMENT_COUNT))) % MOUSE_BODY_SEGMENT_COUNT
    return state.displacement[best_ring][segment]
}

mouse_mailbag_world_point :: proc(
    origin: third_person.Vec3,
    rotation: f32,
    local: third_person.Vec3,
) -> third_person.Vec3 {
    world_x, world_z := world_rotate_xz(origin.x, origin.z, local.x, local.z, rotation)
    return {world_x, origin.y + local.y, world_z}
}
