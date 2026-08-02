package main
import "core:math"

import flight "../packages/flight"
import third_person "../packages/third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_rondine_wake_fans :: proc(editor: ^Editor) {
    if editor == nil || !editor.rondine_visible do return
    rondine_basis := flight.basis_from_orientation(editor.rondine.body.orientation)
    sea_y := editor.project.sea_level + .06
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    // Hold live procedural layouts for four spatial wake samples. At planing
    // speed this produces short coherent spray bursts instead of reseeding
    // every few milliseconds and buzzing between unrelated silhouettes.
    live_spray_epoch := editor.rondine.wake_serial >> 2
    live_spray_blend := clamp(
        (f32(editor.rondine.wake_serial & u32(3)) + clamp(editor.rondine.wake_distance / 1.25, 0, 1)) / 4,
        0,
        1,
    )
    drift_strength := editor.rondine.telemetry.drift_intensity
    countersteer := editor.rondine.telemetry.countersteer
    drift_kick := editor.rondine.telemetry.drift_kick
    hookup_kick := editor.rondine.telemetry.hookup_kick
    surface_impact := editor.rondine.telemetry.surface_impact
    surge_intensity := editor.rondine.telemetry.surge_intensity
    brake_intensity := editor.rondine.telemetry.brake_intensity
    drift_transition := editor.rondine.telemetry.drift_transition
    contact_strength := clamp(
        editor.rondine.telemetry.spray_intensity +
        drift_strength * .38 +
        drift_kick * .34 +
        hookup_kick * .22 +
        surface_impact * .82,
        0,
        1.55,
    )
    world_rondine_wake_contact(editor, sea_y, camera)
    // Straight planing throws a few low, fast needles from the stern. Speed
    // is the reliable source for this always-fresh cue; wake/contact intensity
    // intentionally settles near zero during a stable run. Height and drift
    // still gate it away before flight or asymmetric spray choreography.
    planing_spark_surface := editor.rondine.grounded ? f32(1) : clamp(1 - editor.rondine.telemetry.height / 1.25, 0, 1)
    planing_spark_strength :=
        clamp((editor.rondine.telemetry.speed - 18) / 28, 0, 1) *
        planing_spark_surface *
        clamp(1 - math.abs(editor.rondine.telemetry.slip) * .55 - drift_strength * 2.4, 0, 1)
    if planing_spark_strength > .02 {
        spark_base := third_person.Vec3{editor.rondine.body.position.x, sea_y, editor.rondine.body.position.z}
        spark_back := -world_rondine_surface_heading(editor)
        spark_right := third_person.Vec3{rondine_basis.right.x, 0, rondine_basis.right.z}
        planing_spark_visibility := f32(math.sqrt(f64(planing_spark_strength)))
        for spark in 0 ..< 4 {
            spark_f := f32(spark)
            side_sign := spark & 1 == 0 ? f32(-1) : f32(1)
            variation := world_rondine_live_variation(
                live_spray_epoch,
                live_spray_blend,
                u32(spark & 1),
                u32(210 + spark),
            )
            spark_position :=
                spark_base +
                spark_back * (1.65 + spark_f * .52 + variation * .24) +
                spark_right * (side_sign * (.82 + spark_f * .18 + variation * .18))
            spark_position.y += .18 + spark_f * .045 + variation * .12
            spark_direction :=
                spark_back * (.88 + spark_f * .16 + variation * .22) +
                spark_right * (side_sign * (.38 + spark_f * .13 + variation * .16)) +
                third_person.Vec3{0, .22 + spark_f * .055 + variation * .14, 0}
            spark_alpha := u8(clamp((138 + variation * 64) * planing_spark_visibility, 0, 205))
            world_rondine_spray_streak(
                camera,
                spark_position,
                spark_direction,
                .38 + spark_f * .085 + variation * .12,
                {232, 253, 247, spark_alpha},
            )
        }
    }

    // The twin pushers also cut short rotating ticks into the surface during
    // steady high-speed contact. Unlike the taller contact-spray sheets these
    // are speed-driven, so the full-span engine signature remains present
    // after transient spray intensity settles.
    prop_tick_strength :=
        clamp((editor.rondine.telemetry.speed - 16) / 30 + surge_intensity * .24, 0, 1) * planing_spark_surface
    if prop_tick_strength > .04 {
        prop_tick_base := third_person.Vec3{editor.rondine.body.position.x, sea_y, editor.rondine.body.position.z}
        prop_tick_back := -world_rondine_surface_heading(editor)
        prop_tick_right := third_person.Vec3{rondine_basis.right.x, 0, rondine_basis.right.z}
        prop_tick_visibility := f32(math.sqrt(f64(prop_tick_strength)))
        for side in 0 ..< 2 {
            side_sign := side == 0 ? f32(-1) : f32(1)
            for tick in 0 ..< 2 {
                tick_f := f32(tick)
                prop_phase := math.sin((editor.rondine.propeller_turns + f32(side) * .5 + tick_f * .22) * math.TAU)
                tick_position :=
                    prop_tick_base +
                    prop_tick_right * (side_sign * (3.78 + prop_phase * .12)) +
                    prop_tick_back * (.62 + tick_f * .42)
                tick_position.y += .10 + tick_f * .05 + max(prop_phase, f32(0)) * .10
                tick_direction :=
                    prop_tick_back * (.64 + tick_f * .16) +
                    prop_tick_right * (side_sign * (.28 + prop_phase * .16)) +
                    third_person.Vec3{0, .14 + tick_f * .07 + max(prop_phase, f32(0)) * .12, 0}
                tick_alpha := u8(clamp((118 + tick_f * 26 + prop_phase * 18) * prop_tick_visibility, 0, 176))
                world_rondine_spray_streak(
                    camera,
                    tick_position,
                    tick_direction,
                    .24 + tick_f * .07 + math.abs(prop_phase) * .05,
                    {226, 250, 245, tick_alpha},
                )
                tick_surface_position := tick_position
                tick_surface_position.y = sea_y + .038
                tick_tangent :=
                    prop_tick_back * (.72 + tick_f * .10) + prop_tick_right * (side_sign * (.24 + prop_phase * .12))
                tick_radial := prop_tick_right * side_sign - prop_tick_back * (.10 + tick_f * .04)
                world_rondine_surface_chip(
                    tick_surface_position,
                    tick_tangent,
                    tick_radial,
                    .14 + tick_f * .04 + math.abs(prop_phase) * .025,
                    .028 + prop_tick_visibility * .012,
                    {226, 250, 245, u8(f32(tick_alpha) * .86)},
                    double_sided = true,
                )
            }
        }
    }
    // Opening the throttle compresses a broad transverse patch behind the
    // stern before resolving into the two rotating prop tracks. Three broken
    // bars provide a brief large-to-medium launch cadence; steady cruise
    // drops them completely while retaining the small prop ticks.
    surge_strength := surge_intensity * planing_spark_surface * clamp(1 - drift_strength * 1.8, 0, 1)
    if surge_strength > .04 {
        surge_base := third_person.Vec3{editor.rondine.body.position.x, sea_y + .041, editor.rondine.body.position.z}
        surge_back := -world_rondine_surface_heading(editor)
        surge_right := third_person.Vec3{rondine_basis.right.x, 0, rondine_basis.right.z}
        surge_visibility := f32(math.sqrt(f64(surge_strength)))
        for bar in 0 ..< 3 {
            bar_f := f32(bar)
            side_offset := bar & 1 == 0 ? f32(-1) : f32(1)
            bar_position :=
                surge_base + surge_back * (2.8 + bar_f * .72) + surge_right * (side_offset * (.10 + bar_f * .06))
            bar_tangent := surge_right + surge_back * (side_offset * (.08 + bar_f * .035))
            bar_radial := surge_back - surge_right * (side_offset * .10)
            bar_alpha := u8(clamp((186 - bar_f * 24) * surge_visibility, 0, 202))
            world_rondine_surface_chip(
                bar_position,
                bar_tangent,
                bar_radial,
                1.28 + surge_visibility * .62 - bar_f * .16,
                .105 + surge_visibility * .045 - bar_f * .010,
                {232, 253, 247, bar_alpha},
                double_sided = true,
            )
        }
    }
    // Power-over combines the launch compression with lateral hull load.
    // Rather than drawing the straight transverse bars through a slide, peel
    // that energy into a single outside rooster tail: one broad lifted sheet,
    // several stepped ribs, and a crown of fine droplets.
    power_over_strength := clamp(surge_intensity * drift_strength * 3.2, 0, 1) * planing_spark_surface
    if power_over_strength > .045 {
        power_visibility := f32(math.sqrt(f64(power_over_strength)))
        power_base := third_person.Vec3{editor.rondine.body.position.x, sea_y + .047, editor.rondine.body.position.z}
        power_back := -world_rondine_surface_heading(editor)
        power_right := third_person.Vec3{rondine_basis.right.x, 0, rondine_basis.right.z}
        power_side := math.sign(editor.rondine.steering)
        if math.abs(editor.rondine.telemetry.slip) > .025 {
            power_side = math.sign(editor.rondine.telemetry.slip)
        }
        if power_side == 0 do power_side = 1
        power_root := power_base + power_back * 3.40 + power_right * (power_side * .90)
        power_heel := power_base + power_back * 6.40 + power_right * (power_side * 1.70)
        power_crown := power_base + power_back * 4.40 + power_right * (power_side * (3.25 + power_visibility * 1.10))
        power_crown.y += 1.50 + power_visibility * 2.80
        power_alpha := u8(clamp(206 * power_visibility, 0, 218))
        power_foam := canvas2d.Color{232, 254, 248, power_alpha}
        power_mist := canvas2d.Color{135, 211, 222, u8(f32(power_alpha) * .40)}
        for power_panel in 0 ..< 4 {
            panel_start := f32(power_panel) / 4
            panel_end := f32(power_panel + 1) / 4
            panel_lower_start := power_root + (power_heel - power_root) * panel_start
            panel_lower_end := power_root + (power_heel - power_root) * panel_end
            panel_start_hump := f32(math.sin(f64(panel_start * math.PI)))
            panel_end_hump := f32(math.sin(f64(panel_end * math.PI)))
            panel_upper_start := panel_lower_start + (power_crown - panel_lower_start) * (panel_start_hump * .92)
            panel_upper_end := panel_lower_end + (power_crown - panel_lower_end) * (panel_end_hump * .92)
            panel_lower_clear := canvas2d.Color{power_foam.r, power_foam.g, power_foam.b, u8(f32(power_alpha) * .32)}
            world_rondine_triangle_double_sided(
                panel_lower_start,
                panel_lower_end,
                panel_upper_end,
                panel_lower_clear,
                panel_lower_clear,
                power_mist,
            )
            world_rondine_triangle_double_sided(
                panel_lower_start,
                panel_upper_end,
                panel_upper_start,
                panel_lower_clear,
                power_mist,
                power_foam,
            )
        }
        for rib in 0 ..< 3 {
            rib_f := f32(rib)
            rib_root :=
                power_base + power_back * (3.70 + rib_f * .58) + power_right * (power_side * (1.02 + rib_f * .22))
            rib_tip := rib_root + power_right * (power_side * (.72 + power_visibility * .30))
            rib_tip.y += .30 + power_visibility * (.54 - rib_f * .08)
            rib_width := power_back * (.11 + rib_f * .018)
            rib_color := canvas2d.Color{229, 253, 247, u8(f32(power_alpha) * (.82 - rib_f * .17))}
            world_rondine_triangle_double_sided(
                rib_root - rib_width,
                rib_root + rib_width,
                rib_tip,
                rib_color,
                rib_color,
                {rib_color.r, rib_color.g, rib_color.b, 0},
            )
        }
        for droplet in 0 ..< 5 {
            droplet_f := f32(droplet)
            droplet_position :=
                power_crown +
                power_back * ((droplet_f - 2) * .14) +
                power_right * (power_side * ((droplet_f - 2) * .17))
            droplet_position.y += .10 + (.24 - math.abs(droplet_f - 2) * .045) * power_visibility
            world_rondine_spray_bead(
                camera,
                droplet_position,
                .062 + power_visibility * .031 - math.abs(droplet_f - 2) * .004,
                {231, 254, 248, u8(f32(power_alpha) * (.72 - math.abs(droplet_f - 2) * .075))},
            )
        }
    }
    // When lateral slip crosses through center and loads the opposite side,
    // throw a few lifted beads from the live stern. The decisive crossed
    // slashes and hooks are stamped into wake history below so they stay fixed
    // at the actual crossover instead of sliding along with the aircraft.
    transition_strength := drift_transition * planing_spark_surface
    if transition_strength > .04 {
        transition_visibility := f32(math.sqrt(f64(transition_strength)))
        transition_base := third_person.Vec3 {
            editor.rondine.body.position.x,
            sea_y + .046,
            editor.rondine.body.position.z,
        }
        transition_back := -world_rondine_surface_heading(editor)
        transition_right := third_person.Vec3{rondine_basis.right.x, 0, rondine_basis.right.z}
        transition_side := editor.rondine.slip_side
        if transition_side == 0 do transition_side = math.sign(editor.rondine.steering)
        if transition_side == 0 do transition_side = 1
        transition_alpha := u8(clamp(206 * transition_visibility, 0, 218))
        for bead in 0 ..< 4 {
            bead_f := f32(bead)
            bead_position :=
                transition_base +
                transition_back * (3.72 + bead_f * .24) +
                transition_right * (transition_side * (.72 + bead_f * .21))
            bead_position.y += .24 + transition_visibility * (.28 + bead_f * .08)
            world_rondine_spray_bead(
                camera,
                bead_position,
                .052 + transition_visibility * .025 - bead_f * .003,
                {232, 254, 248, u8(f32(transition_alpha) * (.70 - bead_f * .10))},
            )
        }
    }
    // Chopping the throttle pulls the prop wash inward instead of producing
    // the broad launch-pressure bars. A low suction pocket supplies the large
    // read, paired converging crests the medium read, and short inner teeth
    // carry the pinch into the ordinary prop tracks.
    brake_strength := brake_intensity * planing_spark_surface * clamp(1 - drift_strength * 1.35, 0, 1)
    if brake_strength > .04 {
        brake_base := third_person.Vec3{editor.rondine.body.position.x, sea_y + .039, editor.rondine.body.position.z}
        brake_back := -world_rondine_surface_heading(editor)
        brake_right := third_person.Vec3{rondine_basis.right.x, 0, rondine_basis.right.z}
        brake_visibility := f32(math.sqrt(f64(brake_strength)))
        pocket_alpha := u8(clamp(76 * brake_visibility, 0, 82))
        world_rondine_surface_chip(
            brake_base + brake_back * 3.65,
            brake_right,
            brake_back,
            1.22 + brake_visibility * .52,
            .24 + brake_visibility * .10,
            {42, 112, 121, pocket_alpha},
            double_sided = true,
        )
        for side in 0 ..< 2 {
            side_sign := side == 0 ? f32(-1) : f32(1)
            crest_alpha := u8(clamp(174 * brake_visibility, 0, 188))
            crest_position := brake_base + brake_back * (3.15 + f32(side) * .18) + brake_right * (side_sign * .72)
            crest_tangent := brake_back * .78 - brake_right * (side_sign * .63)
            crest_radial := brake_right * -side_sign + brake_back * .12
            world_rondine_surface_chip(
                crest_position,
                crest_tangent,
                crest_radial,
                .82 + brake_visibility * .28,
                .095 + brake_visibility * .035,
                {224, 249, 244, crest_alpha},
                double_sided = true,
            )
            for tooth in 0 ..< 2 {
                tooth_f := f32(tooth)
                tooth_position :=
                    brake_base +
                    brake_back * (4.05 + tooth_f * .48) +
                    brake_right * (side_sign * (.34 - tooth_f * .11))
                world_rondine_surface_chip(
                    tooth_position,
                    brake_right * -side_sign + brake_back * .24,
                    brake_back,
                    .24 + brake_visibility * .09,
                    .035 + brake_visibility * .012,
                    {232, 253, 247, u8(f32(crest_alpha) * (.82 - tooth_f * .15))},
                    double_sided = true,
                )
            }
        }
    }
    // Steering through the throttle chop tears one edge of the symmetric
    // suction pinch upward. The outside sheet is the large gesture, its
    // staggered surface splinters are the medium cadence, and camera-facing
    // beads supply the brief small-scale glitter at the curling tip.
    brake_flick_strength := brake_strength * clamp(math.abs(editor.rondine.steering) * 2.4, 0, 1)
    if brake_flick_strength > .05 {
        flick_visibility := f32(math.sqrt(f64(brake_flick_strength)))
        flick_base := third_person.Vec3{editor.rondine.body.position.x, sea_y + .045, editor.rondine.body.position.z}
        flick_back := -world_rondine_surface_heading(editor)
        flick_right := third_person.Vec3{rondine_basis.right.x, 0, rondine_basis.right.z}
        flick_side := editor.rondine.steering >= 0 ? f32(1) : f32(-1)
        sheet_root := flick_base + flick_back * 3.05 + flick_right * (flick_side * .72)
        sheet_inner := flick_base + flick_back * 4.25 + flick_right * (flick_side * .28)
        sheet_tip := flick_base + flick_back * 3.72 + flick_right * (flick_side * (1.72 + flick_visibility * .42))
        sheet_tip.y += .42 + flick_visibility * .72
        sheet_alpha := u8(clamp(182 * flick_visibility, 0, 196))
        sheet_foam := canvas2d.Color{229, 252, 246, sheet_alpha}
        sheet_mist := canvas2d.Color{145, 218, 225, u8(f32(sheet_alpha) * .48)}
        world_rondine_triangle_double_sided(
            sheet_root,
            sheet_inner,
            sheet_tip,
            sheet_foam,
            {sheet_foam.r, sheet_foam.g, sheet_foam.b, u8(f32(sheet_alpha) * .66)},
            sheet_mist,
        )
        for splinter in 0 ..< 3 {
            splinter_f := f32(splinter)
            splinter_position :=
                flick_base +
                flick_back * (3.35 + splinter_f * .48) +
                flick_right * (flick_side * (1.02 + splinter_f * .22))
            world_rondine_surface_chip(
                splinter_position,
                flick_back * (.62 + splinter_f * .08) + flick_right * (flick_side * .78),
                flick_right * flick_side - flick_back * .15,
                .36 + flick_visibility * .13 - splinter_f * .035,
                .048 + flick_visibility * .018,
                {230, 253, 247, u8(f32(sheet_alpha) * (.86 - splinter_f * .16))},
                double_sided = true,
            )
        }
        for bead in 0 ..< 4 {
            bead_f := f32(bead)
            bead_position := sheet_tip + flick_back * (bead_f * .17) + flick_right * (flick_side * (bead_f * .15))
            bead_position.y += .08 + bead_f * .13
            world_rondine_spray_bead(
                camera,
                bead_position,
                .055 + flick_visibility * .025 - bead_f * .004,
                {225, 252, 247, u8(f32(sheet_alpha) * (.72 - bead_f * .11))},
            )
        }
    }
    // Historical samples remain fixed in the water after liftoff, but the
    // unsampled stern fan must not follow the aircraft into the air. Taper it
    // through the last meter and a half of ground effect for a clean handoff
    // rather than an abrupt cutoff at the grounded flag.
    live_surface_fraction := clamp(1 - editor.rondine.telemetry.height / 1.5, 0, 1)
    live_strength := editor.rondine.telemetry.wake_intensity * live_surface_fraction
    if live_strength > .02 {
        live_base := third_person.Vec3{editor.rondine.body.position.x, sea_y, editor.rondine.body.position.z}
        live_forward := world_rondine_surface_heading(editor)
        live_right := third_person.Vec3{rondine_basis.right.x, 0, rondine_basis.right.z}
        live_back := -live_forward
        live_turn := clamp(editor.rondine.telemetry.turn_rate * 3 + editor.rondine.telemetry.slip * 1.8, -1, 1)
        for side in 0 ..< 2 {
            side_sign := side == 0 ? f32(-1) : f32(1)
            outside := clamp(1 + side_sign * live_turn * .45, .55, 1.45)
            root := live_base + live_right * (side_sign * .68)
            inner := root + live_back * 2.20 + live_right * (side_sign * .24)
            outer := root + live_back * (4.30 * outside) + live_right * (side_sign * 1.22 * outside)
            crest := root + live_back * (2.85 * outside) + live_right * (side_sign * .72 * outside)
            crest.y += .70 + live_strength * 1.40
            alpha := u8(clamp(48 + 154 * live_strength * outside, 0, 205))
            foam := canvas2d.Color{228, 251, 245, alpha}
            mist := canvas2d.Color{151, 224, 228, u8(f32(alpha) * .64)}
            world_rondine_triangle_colored(root, inner, crest, foam, foam, mist, side == 1)
            world_rondine_triangle_colored(root, crest, outer, foam, mist, {foam.r, foam.g, foam.b, 0}, side == 1)
        }

        // A short chain of boiling foam bridges the live stern burst to the
        // sampled historical churn. Unequal spacing and alternating offsets
        // keep these patches from becoming a painted center stripe.
        for boil in 0 ..< 4 {
            boil_f := f32(boil)
            variation := world_rondine_live_variation(live_spray_epoch, live_spray_blend, 0, u32(40 + boil))
            lateral_variation := variation * 2 - 1
            center :=
                live_base +
                live_back * (1.05 + boil_f * (.72 + variation * .16)) +
                live_right * (lateral_variation * .18)
            center.y += .016
            half_length := .32 + live_strength * .22 + variation * .14
            half_width := .17 + live_strength * .15 + variation * .11
            front := center - live_back * half_length
            rear := center + live_back * half_length
            left := center - live_right * half_width
            right := center + live_right * half_width
            boil_alpha := u8(clamp((158 + variation * 82) * live_strength, 0, 224))
            boil_foam := canvas2d.Color{228, 251, 245, boil_alpha}
            boil_clear := canvas2d.Color{151, 220, 225, 0}
            world_triangle_colored(front, right, rear, boil_clear, boil_foam, boil_clear)
            world_triangle_colored(front, rear, left, boil_clear, boil_clear, boil_foam)
        }

    }
    // Join successive pressure marks into curved ribbons. Building a complete
    // fan at every sample made a hard saw-tooth silhouette during a drift;
    // shared sections keep the wake continuous while preserving its faceted,
    // procedural triangle language.
    world_rondine_wake_history(editor, sea_y, camera)

    world_rondine_wake_events(editor, sea_y, camera)
}
