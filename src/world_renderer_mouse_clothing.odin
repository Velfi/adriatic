package main

import mouse_gait "../packages/mouse_gait"
import mouse_kinematics "../packages/mouse_kinematics"
import mouse_paws "../packages/mouse_paws"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

Mouse_Clothing_Render_Context :: struct {
    using render:                                                                         Mouse_Render_Context,
    animation:                                                                            ^Player_Animation_Tweak,
    emote_pose:                                                                           Mouse_Emote_Pose,
    architecture:                                                                             [5]Mouse_Bone_Pose,
    fur_dark, fur_light, paw:                                                             canvas2d.Color,
    stride_phase:                                                                         f32,
    gait:                                                                                 mouse_gait.Weights,
    model_right:                                                                          third_person.Vec3,
    airborne_weight, horizontal_speed, muzzle_x, muzzle_y, muzzle_z, run_weight:          f32,
    ascent_weight, descent_weight, bound_weight, scurry_weight, walk_weight, trot_weight: f32,
    turn_pose, posted_weight, brake_compression, brake_pose, idle_phase:                  f32,
    softness:                                                                             ^Mouse_Body_Softness_State,
}

world_mouse_clothing_and_limbs :: proc(ctx: Mouse_Clothing_Render_Context) {
    editor, model, p, rotation := ctx.editor, ctx.model, ctx.p, ctx.rotation
    animation := ctx.animation
    emote_pose := ctx.emote_pose
    architecture := ctx.architecture
    fur, fur_dark, fur_light, paw, ear, tooth := ctx.fur, ctx.fur_dark, ctx.fur_light, ctx.paw, ctx.ear, ctx.tooth
    stride_phase, gait := ctx.stride_phase, ctx.gait
    model_forward, model_right := ctx.model_forward, ctx.model_right
    airborne_weight, horizontal_speed := ctx.airborne_weight, ctx.horizontal_speed
    muzzle_x, muzzle_y, muzzle_z, run_weight := ctx.muzzle_x, ctx.muzzle_y, ctx.muzzle_z, ctx.run_weight
    ascent_weight, descent_weight, bound_weight := ctx.ascent_weight, ctx.descent_weight, ctx.bound_weight
    scurry_weight, walk_weight, trot_weight := ctx.scurry_weight, ctx.walk_weight, ctx.trot_weight
    turn_pose, posted_weight := ctx.turn_pose, ctx.posted_weight
    brake_compression, brake_pose, idle_phase := ctx.brake_compression, ctx.brake_pose, ctx.idle_phase
    softness := ctx.softness
    @(no_instrumentation)
    local_point :: #force_inline proc(origin: third_person.Vec3, yaw, x, y, z: f32) -> third_person.Vec3 {
        world_x, world_z := world_rotate_xz(origin.x, origin.z, x, z, yaw)
        return {world_x, origin.y + y, world_z}
    }
    if model.scarf_enabled {
        // The scarf is tied at the neck and has two loose tails.  The tails
        // use local airflow so the same response works as the mouse turns:
        // running speed and the world's wind both feed the flap amplitude.
        scarf := model.scarf_color
        scarf.a = 255
        scarf_dark := color_lerp(scarf, {24, 10, 18, 255}, .42)
        scarf_light := color_lerp(scarf, {255, 224, 211, 255}, .30)
        wind_x, wind_z := editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]
        wind_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
        wind_forward := wind_x * model_forward.x + wind_z * model_forward.z
        wind_right := wind_x * model_right.x + wind_z * model_right.z
        speed_air := horizontal_speed * .42
        wind_air := wind_speed * .075
        flap := clamp(max(speed_air, wind_air), 0, 1)
        // Keep scarf animation local to the rendered mouse. Previously every
        // collar read the player's rotation and every tail shared one phase,
        // which made a group of scarf-wearing mice move as one object.
        position_phase_seed := math.sin(f64(model.position.x) * 12.9898 + f64(model.position.z) * 78.233) * 43758.5453
        scarf_phase_offset := f32(position_phase_seed - math.floor(position_phase_seed)) * math.PI * 2
        scarf_rotation := scarf_phase_offset
        if model.player_controlled {
            scarf_phase_offset = 0
            scarf_rotation = editor.mouse_scarf_rotation
        }
        flap_phase := editor.map_time * (5.2 + flap * 3.8) + wind_forward * .08 + scarf_phase_offset
        sway := math.sin(flap_phase) * (.018 + flap * .055)
        wind_sway := clamp(wind_right * .006, -.07, .07)

        // Ring five of the body hull is the neck cross-section. Recreate that
        // same X/Y ellipse, skin it with the same Neck/Chest weights, and give
        // the scarf width along local Z (the mouse's head-to-tail axis).
        SCARF_COLLAR_SEGMENTS :: 32
        SCARF_NECK_Z :: f32(.10)
        SCARF_NECK_CENTER_Y :: f32(.59)
        SCARF_NECK_RADIUS_X :: f32(.205)
        SCARF_NECK_RADIUS_Y :: f32(.210)
        SCARF_SURFACE_CLEARANCE :: f32(.022)
        SCARF_HALF_WIDTH :: f32(.055)
        collar_rear_local, collar_front_local: [SCARF_COLLAR_SEGMENTS]third_person.Vec3
        collar_rear, collar_front: [SCARF_COLLAR_SEGMENTS]third_person.Vec3
        collar_rear_normal, collar_front_normal: [SCARF_COLLAR_SEGMENTS]third_person.Vec3
        collar_color: [SCARF_COLLAR_SEGMENTS]canvas2d.Color
        for segment in 0 ..< SCARF_COLLAR_SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SCARF_COLLAR_SEGMENTS) + scarf_rotation
            ring_x := math.cos(angle) * (SCARF_NECK_RADIUS_X + SCARF_SURFACE_CLEARANCE)
            ring_y := SCARF_NECK_CENTER_Y + math.sin(angle) * (SCARF_NECK_RADIUS_Y + SCARF_SURFACE_CLEARANCE)
            rear_vertex := Mouse_Skin_Vertex {
                bind_position = {ring_x, ring_y, SCARF_NECK_Z - SCARF_HALF_WIDTH},
                groups        = {{.Neck, .66}, {.Chest, .34}},
            }
            front_vertex := rear_vertex
            front_vertex.bind_position.z = SCARF_NECK_Z + SCARF_HALF_WIDTH
            collar_rear_local[segment] = mouse_skin_vertex(rear_vertex, &architecture)
            collar_front_local[segment] = mouse_skin_vertex(front_vertex, &architecture)
            rear := collar_rear_local[segment]
            front := collar_front_local[segment]
            collar_rear[segment] = local_point(p, rotation, rear.x, rear.y, rear.z)
            collar_front[segment] = local_point(p, rotation, front.x, front.y, front.z)
            light_amount := clamp(.52 + math.cos(angle - .65) * .28 + math.sin(angle) * .12, 0, 1)
            collar_color[segment] = color_lerp(scarf_dark, scarf_light, light_amount)
        }
        for segment in 0 ..< SCARF_COLLAR_SEGMENTS {
            previous := (segment + SCARF_COLLAR_SEGMENTS - 1) % SCARF_COLLAR_SEGMENTS
            next := (segment + 1) % SCARF_COLLAR_SEGMENTS
            around_rear := collar_rear[next] - collar_rear[previous]
            around_front := collar_front[next] - collar_front[previous]
            across := collar_front[segment] - collar_rear[segment]
            collar_rear_normal[segment] = linalg.normalize0(linalg.cross(around_rear, across))
            collar_front_normal[segment] = linalg.normalize0(linalg.cross(around_front, across))
        }
        for segment in 0 ..< SCARF_COLLAR_SEGMENTS {
            next := (segment + 1) % SCARF_COLLAR_SEGMENTS
            world_quad_colored_smooth_lit(
                collar_rear[segment],
                collar_rear[next],
                collar_front[next],
                collar_front[segment],
                collar_rear_normal[segment],
                collar_rear_normal[next],
                collar_front_normal[next],
                collar_front_normal[segment],
                collar_color[segment],
                collar_color[next],
                collar_color[next],
                collar_color[segment],
            )
        }

        // Attach both tails to adjacent points on the dorsal rear edge of the
        // skinned collar. Their roots inherit the exact posed neck location;
        // only the free spans react to speed and wind.
        scarf_sides := [2]f32{-1, 1}
        for side_f, side_index in scarf_sides {
            // Leave the dorsal centerline open for the rear ear. Starting on
            // the upper side quadrants lets each tail pass beneath the ears
            // before the airflow carries it over the back.
            attach_index := SCARF_COLLAR_SEGMENTS / 8
            if side_index == 0 do attach_index = SCARF_COLLAR_SEGMENTS * 3 / 8
            root_local := collar_rear_local[attach_index]
            SCARF_TAIL_POINTS :: 7
            SCARF_BODY_CLEARANCE :: f32(.030)
            tail_center, tail_left, tail_right: [SCARF_TAIL_POINTS]third_person.Vec3
            tail_normal: [SCARF_TAIL_POINTS]third_person.Vec3
            tail_color: [SCARF_TAIL_POINTS]canvas2d.Color
            for point_index in 0 ..< SCARF_TAIL_POINTS {
                amount := f32(point_index) / f32(SCARF_TAIL_POINTS - 1)
                eased := amount * amount * (3 - 2 * amount)
                tail_phase := flap_phase + amount * 2.35 + f32(side_index) * .72
                local_x :=
                    root_local.x +
                    wind_sway * eased +
                    sway * side_f * (amount + eased * .45) +
                    math.sin(tail_phase) * flap * .026 * amount
                local_y := root_local.y - .070 * amount + math.sin(tail_phase * 1.13) * flap * .050 * amount
                local_z := root_local.z - (.500 + flap * .200) * amount + wind_forward * .014 * eased
                if body_y, push_up, body_hit := mouse_body_surface_height(&architecture, local_x, local_y, local_z);
                   body_hit {
                    if push_up {
                        local_y = max(local_y, body_y + SCARF_BODY_CLEARANCE)
                    } else {
                        local_y = min(local_y, body_y - SCARF_BODY_CLEARANCE)
                    }
                }
                width := (.072 + flap * .014) * (1 - amount * .38)
                tail_center[point_index] = local_point(p, rotation, local_x, local_y, local_z)
                tail_left[point_index] = local_point(p, rotation, local_x - width, local_y, local_z)
                tail_right[point_index] = local_point(p, rotation, local_x + width, local_y, local_z)
                tail_color[point_index] = color_lerp(scarf, scarf_light, amount * .72)
            }
            for point_index in 0 ..< SCARF_TAIL_POINTS {
                previous := max(point_index - 1, 0)
                next := min(point_index + 1, SCARF_TAIL_POINTS - 1)
                across := tail_right[point_index] - tail_left[point_index]
                along := tail_center[next] - tail_center[previous]
                tail_normal[point_index] = linalg.normalize0(linalg.cross(across, along))
            }
            for segment in 0 ..< SCARF_TAIL_POINTS - 1 {
                world_quad_colored_smooth_lit(
                    tail_left[segment],
                    tail_right[segment],
                    tail_right[segment + 1],
                    tail_left[segment + 1],
                    tail_normal[segment],
                    tail_normal[segment],
                    tail_normal[segment + 1],
                    tail_normal[segment + 1],
                    tail_color[segment],
                    tail_color[segment],
                    tail_color[segment + 1],
                    tail_color[segment + 1],
                )
                amount := f32(segment) / f32(SCARF_TAIL_POINTS - 1)
                edge_width := .030 * (1 - amount * .35)
                world_box_between(
                    tail_center[segment],
                    tail_center[segment + 1],
                    model_forward,
                    edge_width,
                    edge_width * .68,
                    tail_color[segment],
                )
            }
        }
    }

    world_box_rotated(
        local_point(p, rotation, -.008 + muzzle_x, muzzle_y - .066, muzzle_z - .040),
        {.007, .010, .008},
        rotation,
        tooth,
    )
    world_box_rotated(
        local_point(p, rotation, .008 + muzzle_x, muzzle_y - .066, muzzle_z - .040),
        {.007, .010, .008},
        rotation,
        tooth,
    )

    sides := [2]f32{-1, 1}
    whisker_scale := model.preview ? f32(.38) : f32(1)
    for side_f in sides {
        whisker_root := local_point(p, rotation, side_f * .035 + muzzle_x, muzzle_y, muzzle_z - .025)
        for whisker_index in 0 ..< 3 {
            whisker_phase := editor.map_time * 4.2 + f32(whisker_index) * .82 + side_f * .38 + stride_phase * .18
            whisker_flex := math.sin(whisker_phase) * (.010 + .005 * run_weight)
            whisker_y := muzzle_y - .055 + f32(whisker_index) * .048
            whisker_mid := local_point(
                p,
                rotation,
                side_f * (.19 * whisker_scale + f32(whisker_index) * .012 * whisker_scale) + muzzle_x,
                (muzzle_y + whisker_y) * .5 + whisker_flex,
                muzzle_z - .060,
            )
            whisker_tip := local_point(
                p,
                rotation,
                side_f *
                    (.36 * whisker_scale + f32(whisker_index) * .022 * whisker_scale + whisker_flex * whisker_scale) +
                muzzle_x,
                whisker_y + whisker_flex,
                muzzle_z - .120 - f32(whisker_index) * .012,
            )
            world_box_between(whisker_root, whisker_mid, model_forward, .006, .006, fur_light)
            world_box_between(whisker_mid, whisker_tip, model_forward, .005, .005, fur_light)
        }
    }

    // Mice progress from a four-beat walk through diagonal trot to a bound.
    // Generate all three footfall patterns and blend them by speed so gait
    // transitions do not pop when the controller accelerates.
    air_tuck := airborne_weight * (.13 + ascent_weight * .05 - descent_weight * .085)
    for side_f, side_index in sides {
        left_side := side_f < 0
        // Walk footfalls: LF, RH, RF, LH. Trot synchronizes diagonal pairs;
        // bound synchronizes each homologous pair, fore then hind.
        front_walk_offset := left_side ? f32(0) : f32(.50)
        rear_walk_offset := left_side ? f32(.25) : f32(.75)
        front_trot_offset := left_side ? f32(0) : f32(.50)
        rear_trot_offset := left_side ? f32(.50) : f32(0)
        // Gallop and half-bound are brief transitional gaits in mice. During
        // the trot-to-bound blend, retain a lead-limb split that closes only
        // as full-bound synchronization takes over.
        bilateral_lag := side_f * mouse_gait.bound_bilateral_lag(bound_weight)
        front_motion := mouse_gait.blend_scaled(
            stride_phase,
            front_walk_offset,
            front_trot_offset,
            mouse_gait.BOUND_PHASE_OFFSET + bilateral_lag,
            gait,
            .68,
            .56,
            .34,
            animation.stride_radians_per_meter,
            animation.trot_stride_radians_per_meter,
            animation.bound_stride_radians_per_meter,
        )
        rear_motion := mouse_gait.blend_scaled(
            stride_phase,
            rear_walk_offset,
            rear_trot_offset,
            .50 + mouse_gait.BOUND_PHASE_OFFSET - bilateral_lag,
            gait,
            .76,
            .60,
            .36,
            animation.stride_radians_per_meter,
            animation.trot_stride_radians_per_meter,
            animation.bound_stride_radians_per_meter,
        )
        front_cycle := front_motion.reach * run_weight
        rear_cycle := rear_motion.reach * run_weight
        // Scurry exaggerates the mouse-like catch-and-push shape: the forefeet
        // reach farther to catch the low chest and the long hind feet sweep
        // farther beneath the belly before driving rearward. The asymmetric
        // multipliers keep this from reading as four identical pistons.
        front_cycle *= 1 + scurry_weight * .16
        rear_cycle *= 1 + scurry_weight * .24
        front_lift_scale := .075 * walk_weight + .088 * trot_weight + .145 * bound_weight
        hind_lift_scale := .090 * walk_weight + .105 * trot_weight + .165 * bound_weight
        front_lift := front_motion.lift * front_lift_scale * run_weight * (1 - scurry_weight * .10)
        inside_turn := max(side_f * turn_pose, f32(0))
        outside_turn := max(-side_f * turn_pose, f32(0))
        paw_turn_reach := animation.turn_paw_offset * (outside_turn - inside_turn * .45)
        // Limb roots are anatomical bind points. Gait, turning, and authored
        // poses move their parent bones and distal joints, but must not also
        // translate the socket independently or it separates from the hull.
        fore_socket_bind := third_person.Vec3{side_f * .12, .31, .04}
        posed_fore_socket := mouse_skin_vertex(
            {bind_position = fore_socket_bind, groups = {{.Chest, .68}, {.Spine, .32}}},
            &architecture,
        )
        posed_fore_socket += mouse_body_softness_sample(softness, fore_socket_bind)
        fore_shoulder := local_point(p, rotation, posed_fore_socket.x, posed_fore_socket.y, posed_fore_socket.z)
        if model.player_controlled && model.track_paw_plants {
            mouse_paws.set_evaluated_socket(&editor.player_paws, side_index * 2, fore_shoulder)
        }
        fore_elbow := local_point(
            p,
            rotation,
            side_f * (.095 * (1 - run_weight) + .125 * run_weight + paw_turn_reach * .6) -
            side_f * posted_weight * .018,
            .16 * (1 - run_weight) +
            .155 * run_weight +
            front_lift * .35 +
            air_tuck * .55 -
            brake_compression * .55 -
            inside_turn * .02 +
            posted_weight * .30,
            .17 * (1 - run_weight) +
            (.145 + front_cycle * .090) * run_weight +
            brake_pose * .055 +
            posted_weight * .015,
        )
        idle_groom := math.sin(idle_phase * .78 + side_f * .9) * .009 * (1 - run_weight)
        // An upright mouse keeps its forelegs tucked independently beside the
        // chest. Do not draw the posted paws toward the centerline: that makes
        // the overlapping limb hulls read as human-style folded arms.
        fore_paw_x :=
            side_f * (.09 * (1 - run_weight) + .105 * run_weight + descent_weight * .018 + paw_turn_reach) +
            side_f * posted_weight * .025
        fore_paw_y :=
            .038 * (1 - run_weight) +
            .042 * run_weight +
            front_lift +
            air_tuck +
            idle_groom -
            inside_turn * .018 +
            posted_weight * .355
        fore_paw_z :=
            .29 * (1 - run_weight) +
            (.235 + front_cycle + side_f * .014) * run_weight +
            idle_groom * side_f * .55 +
            brake_pose * .12 -
            posted_weight * .095
        fore_emote := emote_pose.paws[side_index * 2]
        fore_emote_weight := clamp(fore_emote.weight, 0, 1)
        fore_paw_x += fore_emote.local_offset.x * fore_emote_weight
        fore_paw_y += fore_emote.local_offset.y * fore_emote_weight
        fore_paw_z += fore_emote.local_offset.z * fore_emote_weight
        fore_paw := local_point(p, rotation, fore_paw_x, fore_paw_y, fore_paw_z)
        if model.driving_pose {
            // Preserve the anatomical shoulder sockets computed above and
            // place each paw directly on the steering-wheel rim. Convert the
            // car-authored wheel dimensions into the scaled mouse-local frame
            // so the grip cannot drift when either side is adjusted.
            steering := clamp(model.drive_steering, -1, 1)
            wheel_rotation := steering * .55
            neutral_grip_x := side_f * f32(.8660254)
            neutral_grip_up := f32(.5)
            grip_rim_x := neutral_grip_x * math.cos(wheel_rotation) - neutral_grip_up * math.sin(wheel_rotation)
            grip_rim_up := neutral_grip_up * math.cos(wheel_rotation) + neutral_grip_x * math.sin(wheel_rotation)
            grip_point := car_steering_wheel_point(grip_rim_x, grip_rim_up)
            grip_x := grip_point.x / CAR_PILOT_SCALE
            grip_y := (grip_point.y - CAR_PILOT_SEAT_Y) / CAR_PILOT_SCALE
            grip_z := (CAR_PILOT_SEAT_Z - grip_point.z) / CAR_PILOT_SCALE
            fore_paw = local_point(p, rotation, grip_x, grip_y, grip_z)
            // A mouse forelimb reaches from a low shoulder as a soft, shallow
            // chain. Place the elbow along that reach with only a slight sag;
            // a raised midpoint creates an angular, human-like bent arm.
            fore_elbow = third_person.Vec3 {
                fore_shoulder.x * .56 + fore_paw.x * .44,
                fore_shoulder.y * .56 + fore_paw.y * .44 - .018 * CAR_PILOT_SCALE,
                fore_shoulder.z * .56 + fore_paw.z * .44,
            }
        }
        // Decide contact from the final posed height, rather than the raw gait
        // curve. During deceleration run_weight lowers the visible paw before
        // the source cycle reaches stance; using the source lift here made a
        // visibly grounded paw slide with the body.
        // Contact phase comes from the unattenuated gait cycle, not the
        // visibly blended lift. During acceleration run_weight starts near
        // zero; using front_lift here incorrectly pins both forepaws even
        // while one side's underlying gait is already in recovery.
        fore_locomoting := horizontal_speed > .08 || run_weight > .03
        fore_planted :=
            model.grounded &&
            (fore_emote_weight > .5 ? fore_emote.planted : posted_weight < .5 && (!fore_locomoting || front_motion.lift < .025))
        fore_authored := mouse_paws.authored_pose(&editor.player_paws, side_index * 2)
        if model.track_paw_plants && fore_authored.valid {
            fore_paw = fore_authored.desired
            fore_planted = fore_authored.stance
        }
        // Mouse forearms are approximately as long as, or slightly longer
        // than, the humerus. Keep the complete chain compact so the proximal
        // limb remains tucked inside the chest silhouette instead of reading
        // as a long, human-like arm.
        FORE_UPPER_LENGTH :: f32(.235)
        FORE_LOWER_LENGTH :: f32(.235)
        fore_minimum_reach := math.abs(FORE_UPPER_LENGTH - FORE_LOWER_LENGTH) + .0001
        fore_maximum_reach := FORE_UPPER_LENGTH + FORE_LOWER_LENGTH - .0001
        fore_resolved := mouse_paws.resolved_pose(&editor.player_paws, side_index * 2)
        if model.grounded && !(model.track_paw_plants && fore_resolved.valid) {
            fore_paw = mouse_ground_contact(editor, fore_paw, .024, fore_planted)
            mouse_clamp_ground_contact_reach(fore_shoulder, &fore_paw, fore_maximum_reach)
        } else if !(model.track_paw_plants && fore_resolved.valid) {
            mouse_clamp_endpoint_reach(fore_shoulder, &fore_paw, fore_minimum_reach, fore_maximum_reach)
        }
        if model.track_paw_plants && fore_resolved.valid {
            fore_paw = fore_resolved.pad_position
            mouse_clamp_endpoint_reach(fore_shoulder, &fore_paw, fore_minimum_reach, fore_maximum_reach)
        }
        if model.grounded && !(model.track_paw_plants && fore_resolved.valid) {
            fore_paw = mouse_ground_contact(editor, fore_paw, .024, fore_planted)
            mouse_clamp_ground_contact_reach(fore_shoulder, &fore_paw, fore_maximum_reach)
        }
        fore_elbow = mouse_kinematics.solve_two_bone(
            fore_shoulder,
            fore_paw,
            mouse_kinematics.fore_elbow_pole(model_forward),
            FORE_UPPER_LENGTH,
            FORE_LOWER_LENGTH,
        )
        if model.player_controlled {
            mouse_body_softness_accumulate_capsule(
                &editor.player_body_softness,
                p,
                rotation,
                fore_shoulder,
                fore_elbow,
                animation.body_softness_strength,
                animation.body_softness_influence_radius,
            )
        }
        fore_wrist := third_person.Vec3 {
            fore_elbow.x * .30 + fore_paw.x * .70,
            fore_elbow.y * .30 + fore_paw.y * .70,
            fore_elbow.z * .30 + fore_paw.z * .70,
        }
        fore_points := [4]third_person.Vec3{fore_shoulder, fore_elbow, fore_wrist, fore_paw}
        fore_radii := [4]f32{.044, .035, .024, .017}
        fore_socket_color := mouse_limb_socket_color(model.pattern, fur, fur_dark, fur_light, side_f, false)
        fore_colors := [4]canvas2d.Color{fore_socket_color, fur_dark, paw, paw}
        // A compact shoulder bulb overlaps both the skinned chest and the
        // capped limb root. A flat cap alone cannot cover the wedge that
        // opens between those independently posed surfaces at deep flexion.
        shoulder_socket_center := fore_shoulder
        shoulder_socket_center.y += .018
        world_ellipsoid_rotated(shoulder_socket_center, .046, .050, .052, rotation, fore_socket_color, .BRDF)
        world_mouse_limb_hull(fore_points[:], fore_radii[:], fore_colors[:], model_forward)
        // Paws are low pads lying in the ground plane. The former vertical
        // discs presented their extrusion as a rectangular bar in profile.
        if model.track_paw_plants && fore_resolved.valid {
            world_surface_paw_pad(
                fore_paw,
                fore_resolved.pad_normal,
                .044,
                .041,
                .030,
                rotation,
                fore_resolved.compression,
                paw,
            )
        } else {
            world_vertical_prism(fore_paw, .044, .041, .030, rotation, paw)
        }
        for digit in 0 ..< 3 {
            digit_tip := local_point(
                fore_paw,
                rotation,
                side_f * (f32(digit) - 1) * .013,
                -.036 * (1 - run_weight) - .006 * run_weight,
                .018 * (1 - run_weight) + .064 * run_weight,
            )
            if model.track_paw_plants && fore_resolved.valid {
                contact_correction := fore_paw - fore_resolved.pad_position
                digit_tip = fore_resolved.toes[digit].tip + contact_correction
            } else if model.grounded {
                digit_tip = mouse_ground_contact(editor, digit_tip, .008, fore_planted)
            }
            if model.track_paw_plants && fore_resolved.valid {
                contact_correction := fore_paw - fore_resolved.pad_position
                digit_root := fore_resolved.toes[digit].root + contact_correction
                world_tube_between(fore_paw, digit_root, model_forward, .008, .008, paw)
                world_tube_between(digit_root, digit_tip, model_forward, .008, .008, paw)
            } else {
                world_tube_between(fore_paw, digit_tip, model_forward, .008, .008, paw)
            }
        }

        hind_cycle := rear_cycle
        hind_lift := rear_motion.lift * hind_lift_scale * run_weight * (1 + scurry_weight * .12)
        hind_socket_bind := third_person.Vec3{side_f * .16, .30, -.47}
        posed_hind_socket := mouse_skin_vertex(
            {bind_position = hind_socket_bind, groups = {{.Pelvis, .82}, {.Spine, .18}}},
            &architecture,
        )
        posed_hind_socket += mouse_body_softness_sample(softness, hind_socket_bind)
        hind_hip := local_point(p, rotation, posed_hind_socket.x, posed_hind_socket.y, posed_hind_socket.z)
        if model.player_controlled && model.track_paw_plants {
            mouse_paws.set_evaluated_socket(&editor.player_paws, side_index * 2 + 1, hind_hip)
        }
        // The hind leg needs both a forward knee and a rear hock. Collapsing
        // those joints into one segment hides the entire chain inside the
        // haunch in side views and makes the paw appear disconnected.
        hind_knee := local_point(
            p,
            rotation,
            side_f * (.205 + descent_weight * .012 + paw_turn_reach * .48 - posted_weight * .015),
            .18 + hind_lift * .35 + air_tuck * .32 - brake_compression * .25 + posted_weight * .015,
            -.25 + hind_cycle * .13 * run_weight + brake_pose * .105 - posted_weight * .055,
        )
        hind_hock := local_point(
            p,
            rotation,
            side_f * (.22 + descent_weight * .018 + paw_turn_reach * .68 - posted_weight * .040),
            .075 + hind_lift * .60 + air_tuck * .48 - brake_compression * .22,
            -.43 - hind_cycle * .060 * run_weight + brake_pose * .075 - posted_weight * .12,
        )
        hind_paw_x := side_f * (.195 + descent_weight * .025 + paw_turn_reach - posted_weight * .025)
        hind_paw_y := .042 + hind_lift + air_tuck - inside_turn * .014
        // An alert mouse plants its long hind feet forward under the belly;
        // this exposes the toes and supports the raised torso instead of
        // balancing it on two vertical hocks.
        hind_paw_z :=
            -.16 + hind_cycle * run_weight + side_f * .018 * run_weight + brake_pose * .15 + posted_weight * .08
        hind_emote := emote_pose.paws[side_index * 2 + 1]
        hind_emote_weight := clamp(hind_emote.weight, 0, 1)
        hind_paw_x += hind_emote.local_offset.x * hind_emote_weight
        hind_paw_y += hind_emote.local_offset.y * hind_emote_weight
        hind_paw_z += hind_emote.local_offset.z * hind_emote_weight
        hind_paw := local_point(p, rotation, hind_paw_x, hind_paw_y, hind_paw_z)
        if model.driving_pose {
            // Fold the rear legs into the bucket seat. Keeping the hock behind
            // the knee creates a readable seated zig-zag when the cockpit is
            // viewed from either three-quarter angle. Keep the skinned hip
            // socket attached to the pelvis while posing the distal joints.
            hind_knee = local_point(p, rotation, side_f * .205, .19, -.20)
            hind_hock = local_point(p, rotation, side_f * .19, .105, -.36)
            hind_paw = local_point(p, rotation, side_f * .17, .095, -.11)
        }
        // Release both pairs while rising into the posted pose. Otherwise the
        // authored hind-foot shift stretches back toward the last locomotion
        // contact cached in world space.
        hind_planted :=
            model.grounded && (hind_emote_weight > .5 ? hind_emote.planted : hind_lift < .003 && posted_weight < .5)
        hind_authored := mouse_paws.authored_pose(&editor.player_paws, side_index * 2 + 1)
        if model.track_paw_plants && hind_authored.valid {
            hind_paw = hind_authored.desired
            hind_planted = hind_authored.stance
        }
        // Preserve the authored .74 total reach while using mouse-like
        // proportions: a tibia longer than the femur and a long, but not
        // dominant, hock-to-paw segment.
        HIND_LENGTHS :: [3]f32{.220, .270, .250}
        hind_resolved := mouse_paws.resolved_pose(&editor.player_paws, side_index * 2 + 1)
        if model.track_paw_plants && hind_resolved.valid {
            hind_paw = hind_resolved.pad_position
        }
        if model.grounded && !(model.track_paw_plants && hind_resolved.valid) {
            hind_paw = mouse_ground_contact(editor, hind_paw, .024, hind_planted)
        }
        hind_chain := [4]third_person.Vec3{hind_hip, hind_knee, hind_hock, hind_paw}
        mouse_constrain_hind_chain(&hind_chain, HIND_LENGTHS, model_forward)
        hind_hip, hind_knee, hind_hock, hind_paw = hind_chain[0], hind_chain[1], hind_chain[2], hind_chain[3]
        if model.player_controlled {
            mouse_body_softness_accumulate_capsule(
                &editor.player_body_softness,
                p,
                rotation,
                hind_hip,
                hind_knee,
                animation.body_softness_strength,
                animation.body_softness_influence_radius,
            )
        }
        if model.hide_hind_feet {
            // Vehicle seats conceal the folded rear feet. Stop the visible
            // limb at the hock so pads and toes cannot poke through bodywork.
            hind_points := [3]third_person.Vec3{hind_hip, hind_knee, hind_hock}
            hind_radii := [3]f32{.065, .052, .041}
            hind_socket_color := mouse_limb_socket_color(model.pattern, fur, fur_dark, fur_light, side_f, true)
            hind_colors := [3]canvas2d.Color{hind_socket_color, fur, fur_dark}
            world_mouse_limb_hull(hind_points[:], hind_radii[:], hind_colors[:], model_forward, false)
        } else {
            hind_ankle := third_person.Vec3 {
                hind_hock.x * .42 + hind_paw.x * .58,
                hind_hock.y * .42 + hind_paw.y * .58,
                hind_hock.z * .42 + hind_paw.z * .58,
            }
            hind_points := [5]third_person.Vec3{hind_hip, hind_knee, hind_hock, hind_ankle, hind_paw}
            hind_radii := [5]f32{.065, .052, .041, .030, .022}
            hind_socket_color := mouse_limb_socket_color(model.pattern, fur, fur_dark, fur_light, side_f, true)
            hind_colors := [5]canvas2d.Color{hind_socket_color, fur, fur_dark, paw, paw}
            world_mouse_limb_hull(hind_points[:], hind_radii[:], hind_colors[:], model_forward, false)
            if model.track_paw_plants && hind_resolved.valid {
                world_surface_paw_pad(
                    hind_paw,
                    hind_resolved.pad_normal,
                    .058,
                    .058,
                    .032,
                    rotation,
                    hind_resolved.compression,
                    paw,
                )
            } else {
                world_vertical_prism(hind_paw, .058, .058, .032, rotation, paw)
            }
            for digit in 0 ..< 3 {
                digit_tip := local_point(hind_paw, rotation, side_f * (f32(digit) - 1) * .017, -.008, .092)
                if model.track_paw_plants && hind_resolved.valid {
                    contact_correction := hind_paw - hind_resolved.pad_position
                    digit_tip = hind_resolved.toes[digit].tip + contact_correction
                } else if model.grounded {
                    digit_tip = mouse_ground_contact(editor, digit_tip, .009, hind_planted)
                }
                if model.track_paw_plants && hind_resolved.valid {
                    contact_correction := hind_paw - hind_resolved.pad_position
                    digit_root := hind_resolved.toes[digit].root + contact_correction
                    world_tube_between(hind_paw, digit_root, model_forward, .009, .009, paw)
                    world_tube_between(digit_root, digit_tip, model_forward, .009, .009, paw)
                } else {
                    world_tube_between(hind_paw, digit_tip, model_forward, .009, .009, paw)
                }
            }
        }
    }

    // A freshly spawned player can be submitted before its first simulation
    // step. The zero-initialized Verlet points live at world origin, so
    // building a hull from them stretches the root ring across the map and
    // produces a large triangle fan in capture-mode's early frames. Use the
    // authored tail until physics has established a complete local chain.
}
