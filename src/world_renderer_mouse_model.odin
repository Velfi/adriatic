package main
import "core:math"

import atmosphere "../packages/atmosphere"
import mouse_gait "../packages/mouse_gait"
import mouse_kinematics "../packages/mouse_kinematics"
import mouse_paws "../packages/mouse_paws"
import mouse_tail "../packages/mouse_tail"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_mouse_model :: proc(editor: ^Editor, model: Mouse_Model) {
    first_vertex := len(world_renderer.vertices)
    build := model.build
    if build <= 0 do build = 1
    snout_length := model.snout_length
    if snout_length <= 0 do snout_length = 1
    p := model.position
    if model.grounded {
        raw_height := terrain.sample_height(&editor.project, 0, p.x, p.z)
        p.y += mouse_surface_height_for_model(editor, p.x, p.z) - raw_height
    }
    rotation := model.rotation
    @(no_instrumentation)
    local_point :: #force_inline proc(origin: third_person.Vec3, rotation, x, y, z: f32) -> third_person.Vec3 {
        world_x, world_z := world_rotate_xz(origin.x, origin.z, x, z, rotation)
        return {world_x, origin.y + y, world_z}
    }

    fur: canvas2d.Color
    fur_dark: canvas2d.Color
    fur_light: canvas2d.Color
    switch model.fur {
    case .Chestnut:
        fur, fur_dark, fur_light = {132, 107, 84, 255}, {91, 70, 57, 255}, {184, 164, 139, 255}
    case .Silver:
        fur, fur_dark, fur_light = {139, 145, 151, 255}, {83, 90, 98, 255}, {197, 202, 207, 255}
    case .Cream:
        fur, fur_dark, fur_light = {213, 190, 151, 255}, {145, 119, 88, 255}, {241, 224, 190, 255}
    case .Soot:
        fur, fur_dark, fur_light = {59, 63, 69, 255}, {27, 30, 35, 255}, {111, 118, 125, 255}
    case .Russet:
        fur, fur_dark, fur_light = {169, 91, 55, 255}, {103, 51, 37, 255}, {216, 139, 91, 255}
    case .White:
        fur, fur_dark, fur_light = {226, 224, 216, 255}, {157, 154, 150, 255}, {249, 246, 233, 255}
    }
    ear: canvas2d.Color = {188, 126, 123, 255}
    paw: canvas2d.Color = {201, 146, 139, 255}
    features: canvas2d.Color = {35, 32, 30, 255}
    nose: canvas2d.Color = {161, 102, 101, 255}
    tooth: canvas2d.Color = {232, 222, 189, 255}
    leather: canvas2d.Color = {91, 55, 38, 255}
    leather_dark: canvas2d.Color = {58, 38, 31, 255}
    brass: canvas2d.Color = {204, 157, 72, 255}
    goggle_glass: canvas2d.Color = {78, 157, 169, 255}
    model_forward := third_person.Vec3{-math.sin(rotation), 0, math.cos(rotation)}
    emote_pose := Mouse_Emote_Pose {
        breathing_weight = 1,
        blink_weight     = 1,
        idle_weight      = 1,
    }
    if model.player_controlled do emote_pose = mouse_emote_pose(&editor.mouse_emote)
    animation := &editor.tweak.player_animation
    turn_pose :=
        model.player_controlled ? clamp(editor.player_turn_pose, -1, 1) : (model.driving_pose ? clamp(model.drive_steering, -1, 1) : f32(0))
    brake_pose := model.player_controlled ? clamp(editor.player_brake_pose, 0, 1) : f32(0)
    if model.player_controlled && editor.capture_player_turn_left_pose do turn_pose = -1
    if model.player_controlled && editor.capture_player_turn_right_pose do turn_pose = 1
    if model.player_controlled && editor.capture_player_brake_pose do brake_pose = 1
    ground_normal := model.player_controlled ? editor.player.ground_normal : third_person.Vec3{0, 1, 0}
    if ground_normal.y <= .1 do ground_normal = third_person.Vec3{0, 1, 0}
    model_right := third_person.Vec3{math.cos(rotation), 0, math.sin(rotation)}
    normal_forward := ground_normal.x * model_forward.x + ground_normal.z * model_forward.z
    normal_right := ground_normal.x * model_right.x + ground_normal.z * model_right.z
    slope_pitch := math.atan2(normal_forward, ground_normal.y) * animation.slope_alignment
    slope_roll := math.atan2(-normal_right, ground_normal.y) * animation.slope_alignment
    body_roll := slope_roll - turn_pose * animation.turn_lean_radians
    scurry_weight := model.player_controlled ? clamp(editor.player_scurry_weight, 0, 1) : f32(0)
    scurry_lean := model.player_controlled ? clamp(editor.player_scurry_lean, -.12, .32) : f32(0)
    scurry_compression :=
        model.player_controlled ? clamp(editor.player_scurry_compression, -.025, animation.scurry_compression * 1.35) : f32(0)
    drive_reaction := model.driving_pose ? -clamp(model.drive_acceleration, -1, 1) : f32(0)
    spine_side := turn_pose * animation.turn_spine_offset
    brake_compression := brake_pose * animation.brake_compression
    posted_weight :=
        model.player_controlled ? clamp(editor.player_posted_weight, 0, 1) : (model.gait_preview ? f32(0) : f32(1))
    if model.player_controlled && editor.capture_player_posted_pose do posted_weight = 1
    if model.driving_pose {
        // Driving is a supported crouch, not the mouse's ordinary horizontal
        // locomotion pose.  Lift the chest and head while leaving enough
        // forward reach for both paws to stay on the small steering wheel.
        posted_weight = 1
    }

    airborne_weight := model.player_controlled ? editor.player_airborne_weight : f32(0)
    run_weight :=
        model.player_controlled ? editor.player_gait_weight * (1 - airborne_weight) + .88 * airborne_weight : f32(0)
    stride_phase := model.player_controlled ? editor.player_stride_phase : f32(0)
    horizontal_speed := f32(
        math.sqrt(
            f64(
                editor.player.velocity.x * editor.player.velocity.x +
                editor.player.velocity.z * editor.player.velocity.z,
            ),
        ),
    )
    if model.gait_preview {
        stride_phase = model.gait_phase
        horizontal_speed = model.gait_speed
        // Preview actors must be allowed to settle into the idle pose. Forcing
        // full locomotion at zero or near-zero speed makes their planted paws
        // cycle in place and is especially visible during slow stage blocking.
        preview_motion := clamp(horizontal_speed / max(animation.walk_full_speed * .16, f32(.18)), 0, 1)
        run_weight = preview_motion * preview_motion * (3 - 2 * preview_motion)
    }
    gait := mouse_gait_weights(animation, horizontal_speed, airborne_weight)
    walk_weight, trot_weight, bound_weight := gait.walk, gait.trot, gait.bound
    if model.player_controlled && editor.capture_player_walk_pose {
        run_weight = 1
        stride_phase = math.PI * 1.75
        walk_weight = 1
        trot_weight = 0
        bound_weight = 0
    } else if model.player_controlled && editor.capture_player_run_compress_pose {
        run_weight = 1
        stride_phase = math.PI * .50
        walk_weight = 0
        trot_weight = 0
        bound_weight = 1
    } else if model.player_controlled &&
       (editor.capture_player_turn_left_pose || editor.capture_player_turn_right_pose) {
        run_weight = 1
        stride_phase = math.PI * 1.75
        walk_weight = 0
        trot_weight = 0
        bound_weight = 1
    } else if model.player_controlled && editor.capture_player_brake_pose {
        run_weight = 1
        stride_phase = math.PI * .50
        walk_weight = 0
        trot_weight = 0
        bound_weight = 1
    }
    vertical_pose := model.player_controlled ? editor.player_vertical_pose : f32(0)
    if model.player_controlled && (editor.capture_player_jump_pose || editor.capture_player_fall_pose) {
        airborne_weight = 1
        walk_weight = 0
        trot_weight = 0
        bound_weight = 1
        vertical_pose = clamp(
            editor.player.velocity.y / max(editor.tweak.player_animation.vertical_full_speed, f32(.1)),
            -1,
            1,
        )
    }
    jump_rise := vertical_pose * airborne_weight
    ascent_weight := max(jump_rise, f32(0))
    descent_weight := max(-jump_rise, f32(0))

    // A fast mouse does not carry its mass rigidly down the centerline. Each
    // catch briefly loads one side of the shoulder girdle while the haunches
    // counter-shift for the following push. Keep this phase-derived so scurry
    // remains an animation overlay rather than new persistent simulation state.
    scurry_support_phase := math.sin(stride_phase * 2)
    scurry_support_shift := scurry_support_phase * scurry_weight * .030 * (1 - airborne_weight)
    scurry_support_roll := scurry_support_phase * scurry_weight * .055 * (1 - airborne_weight)
    body_roll += scurry_support_roll

    idle_phase := editor.map_time * 2.2
    // Sagittal spinal flexion is pronounced in a bound, but deliberately
    // restrained in alternating walk and trot gaits.
    bound_phase := mouse_gait.bound_animation_phase(stride_phase, bound_weight)
    bound := math.sin(bound_phase) * run_weight * mouse_gait.axial_flex_scale(gait)
    spine_extension := -bound
    bound_aerial_lift := mouse_gait.bound_aerial_weight(bound_phase) * bound_weight * run_weight * .085
    body_bob :=
        (-bound * .018 +
                math.abs(math.sin(stride_phase * 2)) * mouse_gait.vertical_bob_scale(gait) +
                bound_aerial_lift) *
            run_weight +
        math.sin(idle_phase) * .006 * (1 - run_weight) * emote_pose.idle_weight +
        animation.run_body_lift * run_weight * (1 - airborne_weight)
    body_bob -= scurry_compression
    blink_period := f32(4.6)
    blink_time := editor.map_time - f32(math.floor(f64(editor.map_time / blink_period))) * blink_period
    blink_weight := clamp(1 - math.abs(blink_time - .10) / .10, 0, 1) * emote_pose.blink_weight
    if model.player_controlled && editor.capture_player_blink_pose do blink_weight = 1
    sniff := math.sin(editor.map_time * 5.4) * .008 * (1 - run_weight) * emote_pose.idle_weight
    breathing :=
        math.sin(editor.map_time * 1.65) *
        .018 *
        (1 - run_weight) *
        (1 - airborne_weight) *
        emote_pose.breathing_weight
    head_sway := math.sin(stride_phase) * .012 * run_weight
    ear_twitch :=
        math.sin(idle_phase * 1.7) * .006 * (1 - run_weight) * emote_pose.idle_weight +
        math.abs(bound) * .008 +
        blink_weight * .009

    // One connected hull runs from rump to nose. Its rings carry named,
    // normalized vertex groups and are skinned by this five-bone mouse rig.
    head_y :=
        .57 -
        run_weight * .17 -
        spine_extension * .018 * run_weight -
        bound * .012 +
        body_bob +
        airborne_weight * .015 -
        brake_compression * .72 +
        posted_weight * .27
    head_z :=
        .02 +
        run_weight * .18 +
        spine_extension * .150 * run_weight -
        brake_pose * .025 -
        posted_weight * .035 +
        scurry_lean * .18
    if model.driving_pose {
        // Keep the head over the supported chest instead of stretching the
        // entire mouse horizontally toward the windscreen. The forelimbs
        // supply the reach to the controls while the driver remains seated.
        head_y += .005
        head_y -= math.abs(drive_reaction) * .018
        head_z -= .025
        head_z += drive_reaction * .065
    }
    head_turn_x := spine_side * .24
    skeleton := [5]Mouse_Bone_Pose {
        {
            parent = -1,
            bind_position = {0, .40, -.48},
            position = {
                spine_side * .18 - scurry_support_shift,
                .36 - run_weight * .010 + body_bob - bound * .018 - brake_compression * .48 - posted_weight * .015,
                -.48 - spine_extension * .070 * run_weight + brake_pose * .035,
            },
            pitch = bound * .075 + slope_pitch * .65 - posted_weight * .05 + scurry_lean * .45,
            roll = body_roll * .82 - scurry_support_roll * .22,
        },
        {
            parent = 0,
            bind_position = {0, .43, -.25},
            position = {
                spine_side * .48 - scurry_support_shift * .48,
                .39 - run_weight * .035 + body_bob + bound * .025 - brake_compression * .64 + posted_weight * .15,
                -.25 +
                spine_extension * .035 * run_weight +
                brake_pose * .025 -
                posted_weight * .035 +
                drive_reaction * .018,
            },
            pitch = run_weight * .055 + bound * .085 + slope_pitch * .82 - posted_weight * .10 + scurry_lean * .72,
            roll = body_roll,
        },
        {
            parent = 1,
            bind_position = {0, .50, -.04},
            position = {
                spine_side + scurry_support_shift * .30,
                .44 - run_weight * .085 + body_bob + bound * .055 - brake_compression + posted_weight * .25,
                -.04 +
                run_weight * .06 +
                spine_extension * .080 * run_weight -
                brake_pose * .015 -
                posted_weight * .055 +
                drive_reaction * .035,
            },
            pitch = run_weight * .075 + bound * .110 + slope_pitch - posted_weight * .14 + scurry_lean,
            roll = body_roll,
        },
        {
            parent = 2,
            bind_position = {0, .58, .10},
            position = {
                head_sway * .25 + spine_side * .62 + scurry_support_shift * .68,
                .50 - run_weight * .135 + body_bob + bound * .025 - brake_compression * .82 + posted_weight * .27,
                .10 +
                run_weight * .10 +
                spine_extension * .110 * run_weight -
                brake_pose * .02 -
                posted_weight * .055 +
                drive_reaction * .050,
            },
            pitch = run_weight * .085 + bound * .070 + slope_pitch * .72 - posted_weight * .08 + scurry_lean * .82,
            roll = body_roll * .58 + scurry_support_roll * .16,
        },
        {
            parent        = 3,
            bind_position = {0, .69, .20},
            // Sniffing belongs to the head pose so the connected snout hull
            // travels with the nose, whiskers, and teeth attached to its tip.
            position      = {head_sway + head_turn_x, head_y, head_z + .20 + sniff},
            pitch         = run_weight * .055 -
            bound * .060 +
            slope_pitch * .42 +
            scurry_lean * .42,
            roll          = body_roll *
            .22,
        },
    }
    if model.driving_pose {
        // Ease the pelvis-to-neck chain into the same upright arc as the head.
        // These small graded offsets avoid a hinge at the neck while retaining
        // the low haunches that visibly settle into the bucket seat.
        skeleton[1].position.y += .010
        skeleton[1].position.z -= .020
        skeleton[2].position.y += .020
        skeleton[2].position.z -= .045
        skeleton[3].position.y += .030
        skeleton[3].position.z -= .065
    }
    for bone_offset, bone_index in emote_pose.bones {
        weight := clamp(bone_offset.weight, 0, 1)
        skeleton[bone_index].position += bone_offset.position * weight
        skeleton[bone_index].position.y += emote_pose.body_height - emote_pose.body_compression
        skeleton[bone_index].pitch += bone_offset.pitch * weight
        skeleton[bone_index].yaw += bone_offset.yaw * weight
        skeleton[bone_index].roll += bone_offset.roll * weight
    }
    mouse_skeleton_keep_joints_connected(&skeleton)
    if model.player_controlled {
        tail_attachment_bind := third_person.Vec3{0, .28, -.78}
        tail_attachment_local := mouse_skin_vertex(
            {bind_position = tail_attachment_bind, groups = {{.Pelvis, 1}, {.Spine, 0}}},
            &skeleton,
        )
        editor.player_tail.evaluated_attachment = local_point(
            p,
            rotation,
            tail_attachment_local.x,
            tail_attachment_local.y,
            tail_attachment_local.z,
        )
        editor.player_tail.attachment_valid = true
    }
    softness := model.player_controlled ? &editor.player_body_softness : nil
    world_mouse_skinned_hull(p, rotation, &skeleton, fur, fur_dark, fur_light, model.pattern, breathing, softness)
    if model.mailbag_enabled do world_mouse_mailbag(editor, p, rotation, &skeleton)

    ear_offsets := [2]f32{-.125, .125}
    for ear_x, ear_index in ear_offsets {
        side := ear_x / .125
        side_motion := ear_twitch * side
        ear_pose := emote_pose.ears[ear_index]
        ear_pose_weight := clamp(ear_pose.weight, 0, 1)
        // Keep the bilateral ears subtly asymmetric without pulling the far
        // pinna forward through the head silhouette in a true profile.
        ear_swivel := math.sin(idle_phase * 1.18 + side * 1.05) * .010 * (1 - run_weight)
        ear_depth_stagger := side * .015 + ear_swivel
        ear_height_stagger := side < 0 ? f32(.012) : f32(-.005)
        world_mouse_ear(
            p,
            rotation,
            {
                ear_x + head_sway + head_turn_x + ear_pose.position.x * ear_pose_weight,
                head_y +
                .145 +
                side_motion +
                ear_height_stagger -
                airborne_weight * .018 +
                ear_x * math.sin(body_roll) * .65 +
                ear_pose.position.y * ear_pose_weight,
                head_z + .045 + ear_depth_stagger - airborne_weight * .018 + ear_pose.position.z * ear_pose_weight,
            },
            side,
            side_motion,
            ear_pose.yaw * ear_pose_weight,
            ear_pose.roll * ear_pose_weight,
            fur_dark,
            ear,
        )
    }

    // Bind the muzzle features to the same skinned head tip that closes the
    // hull. Reconstructing this point from head_y/head_z ignored head pitch,
    // so the nose floated above the snout during the gathered bound pose.
    posed_muzzle_tip := mouse_skin_vertex(
        {bind_position = {0, .62, .58}, groups = {{.Head, 1}, {.Neck, 0}}},
        &skeleton,
    )
    muzzle_x := posed_muzzle_tip.x
    muzzle_y := posed_muzzle_tip.y + .010
    muzzle_z := posed_muzzle_tip.z
    world_tapered_disc_depth_rotated(
        local_point(p, rotation, muzzle_x, muzzle_y, muzzle_z + .012),
        .028,
        .022,
        .018,
        .015,
        .040,
        rotation,
        nose,
    )
    nostril_offsets := [2]f32{-.011, .011}
    for nostril_x in nostril_offsets {
        world_vertical_disc_rotated(
            local_point(p, rotation, nostril_x + muzzle_x, muzzle_y + .003, muzzle_z + .025),
            .0045,
            .0035,
            .004,
            rotation,
            features,
        )
    }

    eye_offsets := [2]f32{-.165, .165}
    eye_radius_y := .004 + (1 - blink_weight) * .033
    for eye_x in eye_offsets {
        // Faceted ellipsoids keep the lateral eyes round through the complete
        // camera orbit. A side-canted disc only looked correct in exact
        // profile and collapsed into a black bar from the front.
        world_ellipsoid_rotated(
            local_point(
                p,
                rotation,
                eye_x + head_sway + head_turn_x,
                head_y + .018 + eye_x * math.sin(body_roll) * .32,
                head_z + .31,
            ),
            .034,
            eye_radius_y,
            .032,
            rotation,
            features,
        )
    }

    world_mouse_accessory(
        {
            {editor, model, p, rotation, model_forward, fur, ear, tooth},
            head_y,
            head_z,
            head_sway,
            head_turn_x,
            body_roll,
            blink_weight,
            features,
            leather,
            leather_dark,
            goggle_glass,
            brass,
        },
    )

    world_mouse_clothing_and_limbs(
        {
            {editor, model, p, rotation, model_forward, fur, ear, tooth},
            animation,
            emote_pose,
            skeleton,
            fur_dark,
            fur_light,
            paw,
            stride_phase,
            gait,
            model_right,
            airborne_weight,
            horizontal_speed,
            muzzle_x,
            muzzle_y,
            muzzle_z,
            run_weight,
            ascent_weight,
            descent_weight,
            bound_weight,
            scurry_weight,
            walk_weight,
            trot_weight,
            turn_pose,
            posted_weight,
            brake_compression,
            brake_pose,
            idle_phase,
            softness,
        },
    )

    if model.player_controlled && !model.hide_tail && editor.player_tail.initialized {
        tail_points: [mouse_tail.POINT_COUNT]third_person.Vec3
        tail_radii: [mouse_tail.POINT_COUNT]f32
        tail_colors: [mouse_tail.POINT_COUNT]canvas2d.Color
        // Simulation consumes the attachment evaluated by the preceding
        // render, so its chain is one presentation frame behind the body.
        // Move the complete solved shape by the current socket delta before
        // drawing it. This preserves the tail's relative lag and curvature
        // while keeping its root welded to the rump during locomotion.
        attachment_delta := editor.player_tail.evaluated_attachment - editor.player_tail.points[0].position
        for point, tail_index in editor.player_tail.points {
            weight := f32(tail_index) / f32(len(editor.player_tail.points) - 1)
            tail_points[tail_index] = point.position + attachment_delta
            tail_pose_weight := clamp(emote_pose.tail.weight, 0, 1)
            local_side := emote_pose.tail.curl * math.sin(weight * math.PI) * tail_pose_weight
            tail_points[tail_index].x += math.cos(rotation) * local_side * weight
            tail_points[tail_index].z += math.sin(rotation) * local_side * weight
            tail_points[tail_index].y +=
                (emote_pose.tail.lift * math.sin(weight * math.PI) + emote_pose.tail.tip * weight * weight) *
                tail_pose_weight
            // Preserve a readable sub-pixel-safe tip at gameplay distance.
            // The physical taper remains pronounced, but no longer vanishes
            // between low-poly radial facets when the tail lies on pavement.
            tail_radii[tail_index] = editor.tweak.player_tail.radius * (1 - weight * .48)
            tail_colors[tail_index] = paw
            tail_floor :=
                mouse_surface_height_for_model(editor, point.position.x, point.position.z) +
                tail_radii[tail_index] +
                MOUSE_CONTACT_SKIN
            tail_points[tail_index].y = max(tail_points[tail_index].y, tail_floor)
            // At the low gameplay camera, a mathematically tangent tail loses
            // its lower facets to the road depth buffer. Reach full visual
            // clearance over the first few links, then add a slight tapering
            // bias toward the thin tip. The root remains fixed to the rump.
            clearance_weight := clamp(weight * 4, 0, 1)
            tail_points[tail_index].y += clearance_weight * .012 + weight * .012
        }
        // Clearing only the Verlet points is insufficient on a road crown or
        // uneven heightfield: the straight rendered span between two clear
        // endpoints can still pass through a higher patch of ground. Sample
        // each span and lift both of its endpoints by any missing clearance.
        // Two passes also propagate the correction through neighboring spans
        // without changing the physics state or detaching the root.
        for _ in 0 ..< 2 {
            for tail_index in 0 ..< len(tail_points) - 1 {
                for sample_index in 1 ..= 3 {
                    amount := f32(sample_index) * .25
                    sample := third_person.Vec3 {
                        tail_points[tail_index].x * (1 - amount) + tail_points[tail_index + 1].x * amount,
                        tail_points[tail_index].y * (1 - amount) + tail_points[tail_index + 1].y * amount,
                        tail_points[tail_index].z * (1 - amount) + tail_points[tail_index + 1].z * amount,
                    }
                    radius := tail_radii[tail_index] * (1 - amount) + tail_radii[tail_index + 1] * amount
                    floor := mouse_surface_height_for_model(editor, sample.x, sample.z) + radius + MOUSE_CONTACT_SKIN
                    penetration := floor - sample.y
                    if penetration > 0 {
                        // Apply the full correction at both ends so their
                        // interpolation is guaranteed to clear this sample.
                        tail_points[tail_index].y += penetration
                        tail_points[tail_index + 1].y += penetration
                    }
                }
            }
        }
        // Surface clearance may raise the first span. The socket itself is
        // authoritative; never let presentation-only clearance open a seam
        // between the rump and the first tail ring.
        tail_points[0] = editor.player_tail.evaluated_attachment
        world_mouse_limb_hull(tail_points[:], tail_radii[:], tail_colors[:], model_forward)
    } else if !model.hide_tail {
        tail_points: [9]third_person.Vec3
        tail_radii: [9]f32
        tail_colors: [9]canvas2d.Color
        tail_bind_root := third_person.Vec3{0, .28, -.78}
        tail_posed_root := mouse_skin_vertex(
            {bind_position = tail_bind_root, groups = {{.Pelvis, 1}, {.Spine, 0}}},
            &skeleton,
        )
        tail_root_delta := tail_posed_root - tail_bind_root
        tail_points[0] = local_point(p, rotation, tail_posed_root.x, tail_posed_root.y, tail_posed_root.z)
        tail_radii[0] = .027
        tail_colors[0] = paw
        for tail_index in 1 ..= 8 {
            weight := f32(tail_index) / 8
            gait_sway := model.gait_preview ? mouse_gait.tail_counter_sway(stride_phase, weight, gait) : f32(0)
            root_follow := mouse_gait.tail_root_follow(weight)
            tail_points[tail_index] = local_point(
                p,
                rotation,
                math.sin(weight * math.PI) * .13 + gait_sway + tail_root_delta.x * root_follow,
                .28 * (1 - weight) + .035 * weight + tail_root_delta.y * root_follow,
                -.78 - weight * .82 + tail_root_delta.z * root_follow,
            )
            tail_radii[tail_index] = .027 * (1 - weight * .58)
            tail_colors[tail_index] = paw
            if model.grounded {
                surface :=
                    mouse_surface_height_for_model(editor, tail_points[tail_index].x, tail_points[tail_index].z) +
                    tail_radii[tail_index] +
                    MOUSE_CONTACT_SKIN
                tail_points[tail_index].y = max(tail_points[tail_index].y, surface)
            }
        }
        world_mouse_limb_hull(tail_points[:], tail_radii[:], tail_colors[:], model_forward)
    }

    // Apply identity-preserving physiognomy after assembling the complete
    // mouse so facial features, accessories, limbs, and clothing remain
    // attached. Build changes lateral breadth; snout length affects only the
    // face in front of the head joint instead of lengthening the whole torso.
    if math.abs(build - 1) > .0001 || math.abs(snout_length - 1) > .0001 {
        yaw_right := third_person.Vec3{math.cos(rotation), 0, math.sin(rotation)}
        yaw_forward := third_person.Vec3{-math.sin(rotation), 0, math.cos(rotation)}
        snout_root := f32(.20)
        for index in first_vertex ..< len(world_renderer.vertices) {
            vertex := &world_renderer.vertices[index]
            delta := third_person.Vec3{vertex.position[0] - p.x, vertex.position[1] - p.y, vertex.position[2] - p.z}
            local_x := delta.x * yaw_right.x + delta.z * yaw_right.z
            local_z := delta.x * yaw_forward.x + delta.z * yaw_forward.z
            local_x *= build
            if local_z > snout_root {
                local_z = snout_root + (local_z - snout_root) * snout_length
            }
            vertex.position[0] = p.x + yaw_right.x * local_x + yaw_forward.x * local_z
            vertex.position[2] = p.z + yaw_right.z * local_x + yaw_forward.z * local_z

            normal := third_person.Vec3{vertex.normal[0], vertex.normal[1], vertex.normal[2]}
            normal_x := (normal.x * yaw_right.x + normal.z * yaw_right.z) / build
            normal_y := normal.y
            normal_z := normal.x * yaw_forward.x + normal.z * yaw_forward.z
            if local_z > snout_root do normal_z /= snout_length
            length := f32(math.sqrt(f64(normal_x * normal_x + normal_y * normal_y + normal_z * normal_z)))
            if length > .0001 {
                normal_x /= length
                normal_y /= length
                normal_z /= length
                vertex.normal = {
                    yaw_right.x * normal_x + yaw_forward.x * normal_z,
                    normal_y,
                    yaw_right.z * normal_x + yaw_forward.z * normal_z,
                }
            }
        }
    }
    // Mouse primitives historically inherited the generic unshaded material,
    // which prevented fur, paws, clothing, and accessories from responding to
    // local or directional lights. Preserve explicitly authored specialist
    // materials (eyes, caps, signs, and so on), but give ordinary mouse
    // surfaces the shared matte BRDF.
    for index in first_vertex ..< len(world_renderer.vertices) {
        vertex := &world_renderer.vertices[index]
        if vertex.kind == .Unshaded {
            vertex.kind = .BRDF
            vertex.material = {0, .82}
        }
    }
}
