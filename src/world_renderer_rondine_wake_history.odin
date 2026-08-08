package main
import "core:math"

import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

world_rondine_wake_history :: proc(editor: ^Editor, sea_y: f32, camera: Perspective_Camera) {
    for sample_index in 1 ..< editor.rondine.wake_count {
        older := editor.rondine.wake[sample_index - 1]
        newer := editor.rondine.wake[sample_index]
        older_fade_linear := clamp(1 - older.age / older.lifetime, 0, 1)
        newer_fade_linear := clamp(1 - newer.age / newer.lifetime, 0, 1)
        // Foam loses opacity faster than its disturbance loses width. Squared
        // decay keeps the fresh wake bold while letting its broad tail dissolve
        // into the ocean instead of ending as a long, uniformly bright rail.
        older_fade := older_fade_linear * older_fade_linear
        newer_fade := newer_fade_linear * newer_fade_linear
        older_detail_window := max(f32(1.15), older.lifetime * .82)
        newer_detail_window := max(f32(1.15), newer.lifetime * .82)
        older_detail_fade := clamp(1 - older.age / older_detail_window, 0, 1)
        newer_detail_fade := clamp(1 - newer.age / newer_detail_window, 0, 1)
        older_fade *= older_detail_fade * older_detail_fade
        newer_fade *= newer_detail_fade * newer_detail_fade
        if older_fade <= .01 && newer_fade <= .01 do continue
        older_base := third_person.Vec3{older.position.x, sea_y, older.position.z}
        newer_base := third_person.Vec3{newer.position.x, sea_y, newer.position.z}
        // The chase camera can overtake old pressure marks during a sustained
        // drift. Let those sections pass underneath instead of clipping a
        // meter-wide surface triangle against the near plane.
        segment_center := (older_base + newer_base) * .5
        segment_depth := linalg.dot(segment_center - camera.position, camera.forward)
        if segment_depth < 7.5 do continue
        camera_fade := clamp((segment_depth - 7.5) / 5.5, 0, 1)
        // Preserve the broad water response at distance while retiring detail
        // in perceptual order: flecks/curls first, then raised breakers and
        // shards. This prevents far trail sections collapsing into sparkly
        // sub-pixel noise without shortening the readable wake silhouette.
        fine_distance_fade := clamp((95 - segment_depth) / 35, 0, 1)
        medium_distance_fade := clamp((145 - segment_depth) / 60, 0, 1)
        older_fade *= camera_fade
        newer_fade *= camera_fade
        older_right := third_person.Vec3{older.right.x, 0, older.right.z}
        newer_right := third_person.Vec3{newer.right.x, 0, newer.right.z}
        // Stored turn is steering input, whose sign is opposite the resulting
        // yaw rate. Convert it before combining with slip so historical foam
        // stays on the same loaded side as the live spray and rooster crown.
        older_turn := clamp(-older.turn + older.slip * 1.8, -1, 1)
        newer_turn := clamp(-newer.turn + newer.slip * 1.8, -1, 1)
        // The broad center trough intentionally carries less foam than its
        // pressure rails, but close-range planing needs a little aeration so
        // it does not read as an untouched strip of ocean. Deterministic
        // paired bubble chips follow each sampled segment; occasional bead
        // heads suggest bubbles popping above the surface. Both retire with
        // the fine-detail distance band.
        trough_aeration_strength :=
            (older.strength * older_fade + newer.strength * newer_fade) *
            .5 *
            clamp(1 - (math.abs(older.slip) + math.abs(newer.slip)) * .9, .28, 1) *
            fine_distance_fade
        trough_hash := world_rondine_wake_hash(older.serial, 0, 410)
        if trough_aeration_strength > .08 && trough_hash % 4 != 0 {
            trough_segment := newer_base - older_base
            trough_right := linalg.normalize0(older_right + newer_right)
            for bubble in 0 ..< 2 {
                bubble_f := f32(bubble)
                bubble_seed := world_rondine_wake_hash(older.serial, 0, u32(420 + bubble))
                bubble_variation := f32(bubble_seed % 31) / 30
                bubble_along := .28 + bubble_f * .39 + (bubble_variation - .5) * .12
                bubble_side := bubble == 0 ? f32(-1) : f32(1)
                bubble_position :=
                    older_base +
                    trough_segment * bubble_along +
                    trough_right * (bubble_side * (.08 + bubble_variation * .15))
                bubble_position.y += .026
                bubble_alpha := u8(clamp((92 + bubble_variation * 74) * trough_aeration_strength, 0, 158))
                bubble_color := canvas2d.Color{224, 249, 244, bubble_alpha}
                world_rondine_surface_chip(
                    bubble_position,
                    trough_segment + trough_right * (bubble_side * .18),
                    trough_right,
                    .070 + bubble_variation * .052,
                    .026 + trough_aeration_strength * .018,
                    bubble_color,
                    double_sided = true,
                )
                if bubble_seed % 5 == 0 && segment_depth < 72 {
                    pop_position := bubble_position
                    pop_position.y += .045 + bubble_variation * .055
                    world_rondine_spray_bead(
                        camera,
                        pop_position,
                        .020 + bubble_variation * .014,
                        {232, 253, 247, u8(f32(bubble_alpha) * .82)},
                    )
                }
            }
        }
        world_rondine_wake_pressure_sides(
            older,
            newer,
            older_fade,
            newer_fade,
            older_fade_linear,
            newer_fade_linear,
            older_base,
            newer_base,
            older_right,
            newer_right,
            older_turn,
            newer_turn,
            fine_distance_fade,
            medium_distance_fade,
            camera,
        )
        // Recent high-slip samples retain the outboard rake as a sparse chain
        // of fixed skip scars. This bridges the live wing-adjacent burst into
        // the historical trail without drawing a second continuous foam rail.
        outboard_skip_strength :=
            clamp(math.abs(older.slip) * 2.45, 0, 1) * older.strength * older_fade * medium_distance_fade
        outboard_skip_step := older.age < 1.12 && world_rondine_wake_hash(older.serial, 0, 322) % 4 == 1
        if outboard_skip_step && outboard_skip_strength > .14 {
            skip_seed := world_rondine_wake_hash(older.serial, 0, 323)
            skip_variation := f32(skip_seed % 29) / 28
            skip_loaded_side := older.slip < 0 ? f32(-1) : f32(1)
            skip_forward := third_person.Vec3{older.forward.x, 0, older.forward.z}
            skip_center :=
                older_base +
                older_right * (skip_loaded_side * (4.72 + older.age * .18 + skip_variation * .16)) +
                (newer_base - older_base) * (.18 + skip_variation * .28)
            skip_center.y += .040
            skip_tangent :=
                skip_forward * (.76 + skip_variation * .16) +
                older_right * (skip_loaded_side * (.24 + skip_variation * .22))
            skip_radial := older_right * skip_loaded_side - skip_forward * (.12 + skip_variation * .12)
            skip_alpha := u8(clamp((142 + skip_variation * 54) * outboard_skip_strength, 0, 190))
            skip_color := canvas2d.Color{228, 251, 245, skip_alpha}
            world_rondine_surface_chip(
                skip_center,
                skip_tangent,
                skip_radial,
                .20 + outboard_skip_strength * .16 + skip_variation * .08,
                .028 + outboard_skip_strength * .018,
                skip_color,
                double_sided = true,
            )
            // A smaller echo behind the main scar gives each contact a quick
            // two-beat skip instead of a solitary decorative dash.
            if fine_distance_fade > .08 {
                echo_alpha := u8(f32(skip_alpha) * .52 * fine_distance_fade)
                world_rondine_surface_chip(
                    skip_center -
                    skip_forward * (.19 + skip_variation * .09) -
                    older_right * (skip_loaded_side * (.05 + skip_variation * .04)),
                    skip_tangent - older_right * (skip_loaded_side * .10),
                    skip_radial,
                    .12 + outboard_skip_strength * .08,
                    .020 + outboard_skip_strength * .010,
                    {218, 248, 243, echo_alpha},
                    double_sided = true,
                )
            }
        }

        // Hard lateral motion leaves a small suction curl on the unloaded
        // side of the hull path. Three short, age-rotated glints imply a foam
        // hook without drawing a complete ring, and sample-serial phase keeps
        // the mark fixed in world space as the chase camera moves.
        curl_strength := clamp(math.abs(older.slip) * 2.7, 0, 1) * older.strength * older_fade * fine_distance_fade
        if curl_strength > .12 && older.age < 1.18 && older.serial % 3 == 1 {
            older_forward := third_person.Vec3{older.forward.x, 0, older.forward.z}
            unloaded_sign := older_turn >= 0 ? f32(-1) : f32(1)
            curl_seed := world_rondine_wake_hash(older.serial, 0, 120)
            curl_variation := f32(curl_seed % 17) / 16
            curl_center := older_base + older_right * (unloaded_sign * (.34 + older.age * .28 + curl_variation * .12))
            curl_center.y += .038
            curl_radius := .18 + older.age * .16 + curl_variation * .08
            curl_phase := older.age * math.TAU * .72 + f32((curl_seed >> 6) % 31) / 31 * math.TAU
            for curl_tick in 0 ..< 3 {
                tick_f := f32(curl_tick)
                angle := curl_phase + unloaded_sign * (tick_f - 1) * .52
                cosine, sine := math.cos(angle), math.sin(angle)
                radial := older_right * cosine + older_forward * sine
                tangent := (older_right * -sine + older_forward * cosine) * unloaded_sign
                position := curl_center + radial * curl_radius
                tick_alpha := u8(clamp((112 + (2 - tick_f) * 24 + curl_variation * 35) * curl_strength, 0, 178))
                tick_color := canvas2d.Color{229, 252, 246, tick_alpha}
                world_rondine_spray_streak(
                    camera,
                    position,
                    tangent,
                    .075 + curl_strength * .07 + tick_f * .018,
                    tick_color,
                )
            }
        }

        // Samples laid down during active countersteer retain a brief
        // herringbone stitch. Each paired chip crosses the hull path in the
        // correction direction, recording where the pilot caught the slide
        // after the live skim-cuts have vanished from the stern.
        sampled_countersteer :=
            (older.countersteer * older_fade + newer.countersteer * newer_fade) * .5 * medium_distance_fade
        if sampled_countersteer > .08 && older.age < 1.35 && older.serial % 2 == 0 {
            stitch_center := (older_base + newer_base) * .5
            stitch_center.y += .034
            stitch_forward := third_person.Vec3{older.forward.x, 0, older.forward.z}
            stitch_alpha := u8(clamp(176 * sampled_countersteer, 0, 184))
            stitch_color := canvas2d.Color{225, 250, 244, stitch_alpha}
            for stitch_side in 0 ..< 2 {
                side_sign := stitch_side == 0 ? f32(-1) : f32(1)
                position := stitch_center + older_right * (side_sign * (.13 + sampled_countersteer * .08))
                tangent := stitch_forward * .42 + older_right * (side_sign * .82)
                radial := older_right * .42 - stitch_forward * (side_sign * .82)
                world_rondine_surface_chip(
                    position,
                    tangent,
                    radial,
                    .13 + sampled_countersteer * .09,
                    .032 + sampled_countersteer * .018,
                    stitch_color,
                    double_sided = true,
                )
            }
        }

        // A soft pressure trough gives the wake a large-scale water response
        // without filling the fan with white foam. The center is subtly
        // darkened while both edges dissolve completely into the ocean.
        older_trough_seed := world_rondine_wake_hash(older.serial, 0, 210)
        newer_trough_seed := world_rondine_wake_hash(newer.serial, 0, 210)
        // Broad water displacement should roll in coherent cells, not change
        // width at every 1.25m sample. Blend a deterministic value across
        // groups of four samples; smaller foam details retain their sharper
        // per-sample variation on top.
        older_trough_variation := world_rondine_live_variation(
            older.serial >> 2,
            f32(older.serial & u32(3)) / 4,
            0,
            210,
        )
        newer_trough_variation := world_rondine_live_variation(
            newer.serial >> 2,
            f32(newer.serial & u32(3)) / 4,
            0,
            210,
        )
        older_trough_meander := (older_trough_variation * 2 - 1) * (.055 + math.abs(older.slip) * .34)
        newer_trough_meander := (newer_trough_variation * 2 - 1) * (.055 + math.abs(newer.slip) * .34)
        older_trough_center := older_base + older_right * older_trough_meander
        newer_trough_center := newer_base + newer_right * newer_trough_meander
        older_trough_center.y -= .015
        newer_trough_center.y -= .015
        older_trough_width :=
            (.42 + older.age * .52 + older.strength * .24 + math.abs(older.slip) * 1.15) *
            (.84 + older_trough_variation * .32)
        newer_trough_width :=
            (.42 + newer.age * .52 + newer.strength * .24 + math.abs(newer.slip) * 1.15) *
            (.84 + newer_trough_variation * .32)
        older_trough_left := older_trough_center - older_right * older_trough_width
        older_trough_right := older_trough_center + older_right * older_trough_width
        newer_trough_left := newer_trough_center - newer_right * newer_trough_width
        newer_trough_right := newer_trough_center + newer_right * newer_trough_width
        older_trough_energy := clamp(older.strength + math.abs(older.slip) * .72, 0, 1.28)
        newer_trough_energy := clamp(newer.strength + math.abs(newer.slip) * .72, 0, 1.28)
        older_trough_depth_variation := .70 + f32((older_trough_seed >> 8) % 31) / 100
        newer_trough_depth_variation := .70 + f32((newer_trough_seed >> 8) % 31) / 100
        // Rare four-sample low-pressure cells interrupt the long trough at
        // the same spatial scale as its width/meander variation. They never
        // remove the broad silhouette, but stop a far wake from resolving
        // into one uniformly dark triangular strip.
        older_trough_breath := world_rondine_wake_hash(older.serial >> 2, 0, 224) % 7 == 2 ? f32(.48) : f32(1)
        newer_trough_breath := world_rondine_wake_hash(newer.serial >> 2, 0, 224) % 7 == 2 ? f32(.48) : f32(1)
        older_trough_alpha := u8(
            clamp(
                54 *
                older_trough_energy *
                older_fade_linear *
                camera_fade *
                older_trough_depth_variation *
                older_trough_breath,
                0,
                58,
            ),
        )
        newer_trough_alpha := u8(
            clamp(
                54 *
                newer_trough_energy *
                newer_fade_linear *
                camera_fade *
                newer_trough_depth_variation *
                newer_trough_breath,
                0,
                58,
            ),
        )
        older_trough := canvas2d.Color{28, 109, 139, older_trough_alpha}
        newer_trough := canvas2d.Color{28, 109, 139, newer_trough_alpha}
        trough_clear := canvas2d.Color{28, 109, 139, 0}
        world_rondine_triangle_colored(
            older_trough_left,
            newer_trough_left,
            newer_trough_center,
            trough_clear,
            trough_clear,
            newer_trough,
            false,
        )
        world_rondine_triangle_colored(
            older_trough_left,
            newer_trough_center,
            older_trough_center,
            trough_clear,
            newer_trough,
            older_trough,
            false,
        )
        world_rondine_triangle_colored(
            older_trough_center,
            newer_trough_center,
            newer_trough_right,
            older_trough,
            newer_trough,
            trough_clear,
            true,
        )
        world_rondine_triangle_colored(
            older_trough_center,
            newer_trough_right,
            older_trough_right,
            older_trough,
            trough_clear,
            trough_clear,
            true,
        )

        // Hard slides leave sparse pressure knots inside the loaded half of
        // the trough. A dark tapered eye carries the medium-scale mass while
        // a short pale lip on its outside edge makes the rotation readable.
        // The cadence is deliberately slow so these resemble broad vortices,
        // not another row of decorative flecks.
        eddy_strength :=
            clamp(math.abs(older.slip) * 2.8, 0, 1) *
            older.strength *
            older_fade_linear *
            medium_distance_fade *
            camera_fade
        eddy_step := older.age < 2.15 && world_rondine_wake_hash(older.serial, 0, 218) % 6 == 1
        if eddy_step && eddy_strength > .12 {
            eddy_seed := world_rondine_wake_hash(older.serial, 0, 219)
            eddy_variation := f32(eddy_seed % 29) / 28
            eddy_loaded_sign := older_turn < 0 ? f32(-1) : f32(1)
            eddy_forward := third_person.Vec3{older.forward.x, 0, older.forward.z}
            eddy_center :=
                older_trough_center +
                older_right * (eddy_loaded_sign * older_trough_width * (.28 + eddy_variation * .19))
            eddy_center.y += .017
            eddy_tangent :=
                eddy_forward * (.82 + eddy_variation * .12) +
                older_right * (eddy_loaded_sign * (.18 + eddy_variation * .24))
            eddy_radial := older_right * eddy_loaded_sign - eddy_forward * (.10 + eddy_variation * .14)
            eddy_alpha := u8(clamp((48 + eddy_variation * 34) * eddy_strength, 0, 76))
            world_rondine_surface_chip(
                eddy_center,
                eddy_tangent,
                eddy_radial,
                .34 + eddy_strength * .28 + eddy_variation * .14,
                .12 + eddy_strength * .08,
                {25, 101, 133, eddy_alpha},
                double_sided = true,
            )
            lip_alpha := u8(clamp((126 + eddy_variation * 48) * eddy_strength, 0, 168))
            world_rondine_surface_chip(
                eddy_center +
                older_right * (eddy_loaded_sign * (.13 + eddy_strength * .08)) +
                eddy_forward * (.06 + eddy_variation * .08),
                eddy_tangent + older_right * (eddy_loaded_sign * .18),
                eddy_radial,
                .19 + eddy_strength * .13 + eddy_variation * .07,
                .024 + eddy_strength * .014,
                {213, 246, 242, lip_alpha},
                double_sided = true,
            )
            // Two offset curl fragments complete a broken orbital gesture
            // around the pressure eye. Unequal radii and fading keep the
            // three-beat mark from reading as a literal ring or repeated icon.
            for curl in 0 ..< 2 {
                curl_f := f32(curl)
                curl_side := curl == 0 ? f32(-1) : f32(1)
                curl_center :=
                    eddy_center +
                    eddy_forward * (curl_side * (.22 + curl_f * .09 + eddy_variation * .06)) +
                    older_right * (eddy_loaded_sign * (.18 + curl_f * .13 + eddy_variation * .08))
                curl_center.y += .010 + curl_f * .006
                curl_tangent :=
                    eddy_forward * (.34 + curl_f * .16) -
                    older_right * (eddy_loaded_sign * curl_side * (.78 - curl_f * .10))
                curl_radial := older_right * eddy_loaded_sign + eddy_forward * (curl_side * .24)
                curl_alpha := u8(clamp(f32(lip_alpha) * (.92 - curl_f * .22), 0, 168))
                world_rondine_surface_chip(
                    curl_center,
                    curl_tangent,
                    curl_radial,
                    .22 + eddy_strength * .16 - curl_f * .022,
                    .032 + eddy_strength * .016,
                    {213, 246, 242, curl_alpha},
                    double_sided = true,
                )
            }
        }

        // Broken center churn records the actual curved hull path between the
        // two pressure ribbons. Deliberate gaps keep it foam-like instead of
        // turning the wake into a continuous painted stripe.
        churn_hash := world_rondine_wake_hash(older.serial, 0, 4)
        churn_step := churn_hash % 7 < 3
        churn_strength := (older.strength * older_fade + newer.strength * newer_fade) * .5
        if churn_step && churn_strength > .07 && older.age < 1.45 {
            alternating := churn_hash & 1 == 0 ? f32(-1) : f32(1)
            older_width := .16 + older.age * .11 + churn_strength * .24
            newer_width := .16 + newer.age * .11 + churn_strength * .24
            older_center := older_base + older_right * (alternating * .13)
            newer_center := newer_base + newer_right * (alternating * -.13)
            older_center.y += .022
            newer_center.y += .022
            older_left := older_center - older_right * older_width
            older_right_edge := older_center + older_right * older_width
            newer_left := newer_center - newer_right * newer_width
            newer_right_edge := newer_center + newer_right * newer_width
            churn_alpha := u8(clamp(178 * churn_strength, 0, 188))
            churn_aeration := clamp((older_fade_linear + newer_fade_linear) * .68, 0, 1)
            churn_foam := canvas2d.Color {
                u8(174 + churn_aeration * 52),
                u8(225 + churn_aeration * 24),
                u8(229 + churn_aeration * 14),
                churn_alpha,
            }
            churn_clear := canvas2d.Color {
                u8(145 + churn_aeration * 12),
                u8(210 + churn_aeration * 11),
                u8(219 + churn_aeration * 6),
                u8(f32(churn_alpha) * .14),
            }
            world_triangle_colored(older_left, newer_left, newer_right_edge, churn_clear, churn_foam, churn_foam)
            world_triangle_colored(
                older_left,
                newer_right_edge,
                older_right_edge,
                churn_clear,
                churn_foam,
                churn_clear,
            )

            // One compact aerated boil interrupts the segment silhouette.
            // It carries some of the center energy as a discrete patch after
            // reducing the packet duty cycle above, avoiding both an empty
            // trail and long joined strips.
            boil_variation := f32((churn_hash >> 6) % 29) / 28
            boil_center := older_center + (newer_center - older_center) * (.28 + boil_variation * .44)
            boil_center += older_right * ((boil_variation * 2 - 1) * .11)
            boil_center.y += .012
            boil_tangent := newer_center - older_center + older_right * ((boil_variation * 2 - 1) * .18)
            boil_radial := older_right - boil_tangent * .06
            boil_alpha := u8(f32(churn_alpha) * (.74 + boil_variation * .18))
            world_rondine_surface_chip(
                boil_center,
                boil_tangent,
                boil_radial,
                .11 + churn_strength * .10 + boil_variation * .05,
                .050 + churn_strength * .025,
                {churn_foam.r, churn_foam.g, churn_foam.b, boil_alpha},
            )
        }

        // Straight-line planing needs a medium-scale cadence of its own.
        // Sparse paired transom chevrons imply rapid pressure pulses without
        // becoming continuous rails. As slip rises they yield completely to
        // the asymmetric breakers, claws, and drift crown.
        planing_alignment := clamp(1 - max(math.abs(older.slip), math.abs(newer.slip)) * 7.5, 0, 1)
        planing_pulse :=
            (older.strength * older_fade + newer.strength * newer_fade) * .5 * planing_alignment * medium_distance_fade
        planing_step := older.serial % 2 == 1 && older.age < 1.45
        if planing_step && planing_pulse > .12 {
            pulse_center := (older_base + newer_base) * .5
            pulse_center.y += .034
            pulse_forward := third_person.Vec3{older.forward.x, 0, older.forward.z}
            pulse_visibility := f32(math.sqrt(f64(planing_pulse)))
            pulse_alpha := u8(clamp(208 * pulse_visibility, 0, 208))
            pulse_color := canvas2d.Color{224, 250, 244, pulse_alpha}
            pulse_width := .64 + older.age * .38 + planing_pulse * .24
            for side in 0 ..< 2 {
                side_sign := side == 0 ? f32(-1) : f32(1)
                pulse_position := pulse_center + older_right * (side_sign * pulse_width)
                pulse_tangent := pulse_forward * .46 + older_right * (side_sign * .84)
                pulse_radial := older_right * side_sign - pulse_forward * .18
                world_rondine_surface_chip(
                    pulse_position,
                    pulse_tangent,
                    pulse_radial,
                    .25 + pulse_visibility * .15,
                    .048 + pulse_visibility * .024,
                    pulse_color,
                    double_sided = true,
                )
            }
        }

        // The twin pushers leave a second, wider cadence than the transom
        // chevrons. Sparse crossed pulses sit beneath the two downwash tracks,
        // giving straight planing a recognizable engine signature while the
        // strong slip gate prevents them leaking into drift choreography.
        prop_track_step := older.serial % 4 == 0 && older.age < .96
        if prop_track_step && planing_pulse > .14 {
            prop_track_forward := third_person.Vec3{older.forward.x, 0, older.forward.z}
            prop_track_visibility := f32(math.sqrt(f64(planing_pulse)))
            for track_side in 0 ..< 2 {
                side_sign := track_side == 0 ? f32(-1) : f32(1)
                track_seed := world_rondine_wake_hash(older.serial, u32(track_side), 334)
                track_variation := f32(track_seed % 23) / 22
                track_center :=
                    older_base +
                    (newer_base - older_base) * (.24 + track_variation * .34) +
                    older_right * (side_sign * (2.10 + older.age * .16 + track_variation * .12))
                track_center.y += .036
                track_alpha := u8(clamp((126 + track_variation * 42) * prop_track_visibility, 0, 158))
                track_color := canvas2d.Color{220, 248, 243, track_alpha}
                first_tangent := prop_track_forward * .72 + older_right * (side_sign * .42)
                first_radial := older_right * side_sign - prop_track_forward * .18
                second_tangent := prop_track_forward * .66 - older_right * (side_sign * .38)
                second_radial := older_right * side_sign + prop_track_forward * .16
                world_rondine_surface_chip(
                    track_center,
                    first_tangent,
                    first_radial,
                    .12 + prop_track_visibility * .075 + track_variation * .035,
                    .022 + prop_track_visibility * .010,
                    track_color,
                    double_sided = true,
                )
                world_rondine_surface_chip(
                    track_center - prop_track_forward * .035,
                    second_tangent,
                    second_radial,
                    .10 + prop_track_visibility * .060,
                    .019 + prop_track_visibility * .009,
                    {track_color.r, track_color.g, track_color.b, u8(f32(track_alpha) * .72)},
                    double_sided = true,
                )
            }
        }

        // A committed carve sits between planing chevrons and full drift
        // turbulence. Three-chip scallops gather on the loaded edge, replacing
        // the single bright rail with discrete curved pressure pulses. Deep
        // slip retires them before the drift claws and breakers take over.
        carve_slip := max(math.abs(older.slip), math.abs(newer.slip))
        carve_entry := clamp((carve_slip - .035) / .075, 0, 1)
        carve_exit := clamp((.24 - carve_slip) / .075, 0, 1)
        carve_pulse :=
            (older.strength * older_fade + newer.strength * newer_fade) *
            .5 *
            carve_entry *
            carve_exit *
            medium_distance_fade
        carve_step := older.serial % 3 == 2 && older.age < 1.12
        if carve_step && carve_pulse > .10 {
            loaded_sign := older_turn >= 0 ? f32(1) : f32(-1)
            carve_center := (older_base + newer_base) * .5
            carve_forward := third_person.Vec3{older.forward.x, 0, older.forward.z}
            carve_center += older_right * (loaded_sign * (.72 + older.age * .34 + carve_pulse * .22))
            carve_center.y += .036
            carve_visibility := f32(math.sqrt(f64(carve_pulse)))
            carve_alpha := u8(clamp(184 * carve_visibility, 0, 188))
            carve_color := canvas2d.Color{227, 251, 245, carve_alpha}
            for scallop in 0 ..< 3 {
                scallop_f := f32(scallop)
                arc := scallop_f - 1
                position :=
                    carve_center +
                    carve_forward * (arc * (.17 + older.age * .04)) +
                    older_right * (loaded_sign * (1 - math.abs(arc)) * .08)
                tangent :=
                    carve_forward * (.38 + scallop_f * .12) + older_right * (loaded_sign * (.78 - scallop_f * .18))
                radial := older_right * loaded_sign - carve_forward * (arc * .16)
                world_rondine_surface_chip(
                    position,
                    tangent,
                    radial,
                    .14 + carve_visibility * .09 - math.abs(arc) * .012,
                    .032 + carve_visibility * .015,
                    {carve_color.r, carve_color.g, carve_color.b, u8(f32(carve_alpha) * (1 - math.abs(arc) * .16))},
                    double_sided = true,
                )
            }
        }
    }
}
