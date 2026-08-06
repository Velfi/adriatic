package main
import "core:math"

import flight "../packages/flight"
import third_person "zelda_engine:third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_rondine_wake_contact :: proc(editor: ^Editor, sea_y: f32, camera: Perspective_Camera) {
    rondine_basis := flight.basis_from_orientation(editor.rondine.body.orientation)
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
    contact_strength := clamp(
        editor.rondine.telemetry.spray_intensity +
        drift_strength * .38 +
        drift_kick * .34 +
        hookup_kick * .22 +
        surface_impact * .82,
        0,
        1.55,
    )
    if contact_strength > .02 {
        contact_base := third_person.Vec3{editor.rondine.body.position.x, sea_y, editor.rondine.body.position.z}
        body_forward := third_person.Vec3{rondine_basis.forward.x, 0, rondine_basis.forward.z}
        contact_forward := world_rondine_surface_heading(editor)
        contact_right := third_person.Vec3{rondine_basis.right.x, 0, rondine_basis.right.z}
        contact_back := -contact_forward
        body_back := -body_forward
        stern := contact_base + body_back * 3.7

        // A landing slaps the full hull footprint into the surface. Radial
        world_rondine_wake_landing(
            camera,
            contact_base,
            contact_forward,
            contact_right,
            contact_back,
            stern,
            surface_impact,
            live_spray_epoch,
            live_spray_blend,
        )
        // The forward chines touch first while planing. Two narrow whiskers
        // begin beneath the nose and stream aft into the larger stern sheets,
        // visually attaching the entire effect to the hull. Their low profile
        // keeps them distinct from the tall, drift-only rooster crown.
        chine_surface_fraction := clamp(1 - editor.rondine.telemetry.height / 1.35, 0, 1)
        chine_strength :=
            clamp(editor.rondine.telemetry.wake_intensity * .88 + drift_strength * .16, 0, 1) * chine_surface_fraction
        if chine_strength > .08 {
            for side in 0 ..< 2 {
                side_sign := side == 0 ? f32(-1) : f32(1)
                variation := world_rondine_live_variation(live_spray_epoch, live_spray_blend, u32(side), 20)
                root := contact_base + body_forward * (1.32 + variation * .18) + contact_right * (side_sign * .46)
                tail :=
                    root +
                    contact_back * (1.18 + chine_strength * .92 + variation * .24) +
                    contact_right * (side_sign * (.13 + variation * .10))
                crest := root + (tail - root) * (.42 + variation * .10)
                crest.y += .08 + chine_strength * .24 + variation * .07
                chine_alpha := u8(clamp((102 + variation * 62) * chine_strength, 0, 164))
                chine_foam := canvas2d.Color{226, 250, 244, chine_alpha}
                chine_mist := canvas2d.Color{143, 216, 223, u8(f32(chine_alpha) * .42)}
                chine_clear := canvas2d.Color{chine_foam.r, chine_foam.g, chine_foam.b, 0}
                world_rondine_triangle_colored(root, tail, crest, chine_foam, chine_clear, chine_mist, side == 1)
                whisker_direction :=
                    contact_back * (.72 + variation * .22) +
                    contact_right * (side_sign * (.17 + variation * .16)) +
                    third_person.Vec3{0, .08 + variation * .10, 0}
                world_rondine_spray_streak(
                    camera,
                    crest,
                    whisker_direction,
                    .10 + chine_strength * .09 + variation * .045,
                    chine_foam,
                )
            }
        }

        for side in 0 ..< 2 {
            side_sign := side == 0 ? f32(-1) : f32(1)
            root := stern + contact_right * (side_sign * .62)
            inner := root + contact_back * (1.60 + contact_strength * 2.20)
            crest :=
                root +
                contact_back * (1.40 + contact_strength * 3.40) +
                contact_right * (side_sign * (.40 + contact_strength * 1.15))
            crest.y += .40 + contact_strength * 2.40
            alpha := u8(clamp(158 + contact_strength * 105, 0, 244))
            foam := canvas2d.Color{226, 249, 243, alpha}
            mist := canvas2d.Color{147, 220, 226, u8(f32(alpha) * .52)}
            world_rondine_triangle_colored(root, inner, crest, foam, foam, mist, side == 1)
        }

        // Mid-slip carve pressure gathers into one low loaded-side shoulder.
        // It rises above planing chevrons but stays decisively below the
        // multi-panel hero crown reserved for an actual loss of grip.
        live_slip := math.abs(editor.rondine.telemetry.slip)
        carve_entry := clamp((live_slip - .055) / .075, 0, 1)
        carve_exit := clamp((.245 - live_slip) / .085, 0, 1)
        carve_shoulder_strength :=
            carve_entry * carve_exit * clamp(contact_strength * .58 + drift_strength * .44, 0, 1)
        if carve_shoulder_strength > .04 {
            carve_loaded_side := editor.rondine.telemetry.slip < 0 ? f32(-1) : f32(1)
            shoulder_visibility := f32(math.sqrt(f64(carve_shoulder_strength)))
            shoulder_root := stern + contact_right * (carve_loaded_side * .48)
            shoulder_foot :=
                shoulder_root +
                contact_back * (1.28 + carve_shoulder_strength * .72) +
                contact_right * (carve_loaded_side * (.58 + carve_shoulder_strength * .36))
            shoulder_crest := (shoulder_root + shoulder_foot) * .5
            shoulder_crest += contact_right * (carve_loaded_side * (.12 + carve_shoulder_strength * .10))
            shoulder_crest.y += .32 + carve_shoulder_strength * .92
            shoulder_alpha := u8(clamp((116 + carve_shoulder_strength * 62) * shoulder_visibility, 0, 158))
            shoulder_foam := canvas2d.Color{224, 249, 244, shoulder_alpha}
            shoulder_mist := canvas2d.Color{166, 226, 230, u8(f32(shoulder_alpha) * .54)}
            shoulder_clear := canvas2d.Color{shoulder_foam.r, shoulder_foam.g, shoulder_foam.b, 0}
            world_rondine_triangle_double_sided(
                shoulder_root,
                shoulder_foot,
                shoulder_crest,
                shoulder_foam,
                shoulder_clear,
                shoulder_mist,
            )
            shoulder_direction :=
                contact_back * .62 + contact_right * (carve_loaded_side * .48) + third_person.Vec3{0, .10, 0}
            world_rondine_spray_streak(
                camera,
                shoulder_crest,
                shoulder_direction,
                .13 + carve_shoulder_strength * .16,
                {233, 253, 247, u8(clamp(176 * shoulder_visibility, 0, 184))},
            )
        }

        // A hard slide throws a brief crown of overlapping sheets from the
        // loaded side of the stern. Three unequal prongs give the active drift
        // a hero-scale accent while remaining dormant during normal planing.
        deep_slip_gate := clamp((live_slip - .16) / .18, 0, 1)
        if drift_strength > .22 && deep_slip_gate > .01 || drift_kick > .05 {
            loaded_side := editor.rondine.telemetry.slip < 0 ? f32(-1) : f32(1)
            // Drift intensity spends much of a controllable sustained slide in
            // the .3-.6 range. Starting the visual ramp at .35 left that useful
            // handling band with an almost transparent crown, even though the
            // wake geometry was already fully established. Bring the large
            // silhouette in earlier; the separate kick rays still reserve the
            // sharpest burst for the instant grip breaks.
            crown_strength := max(clamp((drift_strength - .18) / .62, 0, 1) * deep_slip_gate, drift_kick)
            crown_visibility := f32(math.sqrt(f64(crown_strength)))
            crown_mirrored := loaded_side > 0

            // A broken crescent joins the three hero prongs into one readable
            // loaded-side silhouette. Each translucent panel follows the same
            // rising-and-falling arc, with narrow water-colored gaps between
            // panels so it still reads as torn spray rather than a solid sail.
            // Keeping it behind the brighter prongs creates a proper
            // large/medium hierarchy at normal chase-camera distance.
            for panel in 0 ..< 5 {
                panel_f := f32(panel)
                arc_start := .035 + panel_f * .19
                arc_end := arc_start + .205
                start_hump := f32(math.sin(f64(arc_start * math.PI)))
                end_hump := f32(math.sin(f64(arc_end * math.PI)))
                lower_start :=
                    stern +
                    contact_right * (loaded_side * (.64 + arc_start * (3.35 + crown_strength * .90))) +
                    contact_back * (.38 + arc_start * (3.70 + crown_strength * 1.55))
                lower_end :=
                    stern +
                    contact_right * (loaded_side * (.64 + arc_end * (3.35 + crown_strength * .90))) +
                    contact_back * (.38 + arc_end * (3.70 + crown_strength * 1.55))
                // Pinch the top edge toward the panel center and sweep it
                // outward/back. A full-width vertical top made these panels
                // look like translucent fins; this trapezoidal lean reads as
                // water being peeled off the loaded chine at speed.
                panel_center := (lower_start + lower_end) * .5
                upper_start :=
                    panel_center +
                    (lower_start - panel_center) * .56 +
                    contact_right * (loaded_side * (.12 + crown_strength * .16)) +
                    contact_back * (.18 + panel_f * .08)
                upper_end :=
                    panel_center +
                    (lower_end - panel_center) * .56 +
                    contact_right * (loaded_side * (.12 + crown_strength * .16)) +
                    contact_back * (.18 + panel_f * .08)
                upper_start.y += .35 + start_hump * (1.05 + crown_strength * 2.35)
                upper_end.y += .35 + end_hump * (1.05 + crown_strength * 2.35)
                curtain_alpha := u8(clamp((142 + start_hump * 76 - panel_f * 4) * crown_visibility, 0, 210))
                curtain_foam := canvas2d.Color{224, 250, 244, curtain_alpha}
                curtain_mist := canvas2d.Color{164, 226, 230, u8(f32(curtain_alpha) * .52)}
                curtain_clear := canvas2d.Color{curtain_foam.r, curtain_foam.g, curtain_foam.b, 0}
                world_rondine_triangle_double_sided(
                    lower_start,
                    lower_end,
                    upper_end,
                    curtain_clear,
                    curtain_clear,
                    curtain_mist,
                )
                world_rondine_triangle_double_sided(
                    lower_start,
                    upper_end,
                    upper_start,
                    curtain_clear,
                    curtain_mist,
                    curtain_foam,
                )
                crest_direction := upper_end - upper_start
                crest_alpha := u8(clamp((198 + start_hump * 54 - panel_f * 5) * crown_visibility, 0, 236))
                world_rondine_spray_streak(
                    camera,
                    (upper_start + upper_end) * .5,
                    crest_direction,
                    .17 + crown_strength * .16 + start_hump * .060,
                    {235, 254, 248, crest_alpha},
                )
            }

            for prong in 0 ..< 3 {
                prong_f := f32(prong)
                root := stern + contact_right * (loaded_side * (.48 + prong_f * .22)) + contact_back * (prong_f * .18)
                foot :=
                    root +
                    contact_back * (2.20 + prong_f * .94 + crown_strength * 1.55) +
                    contact_right * (loaded_side * (.90 + prong_f * .58))
                crest := (root + foot) * .5
                crest += contact_right * (loaded_side * (.18 + prong_f * .12))
                crest.y += .85 + crown_strength * (2.65 - prong_f * .25)
                crown_alpha := u8(clamp((228 - prong_f * 22) * crown_visibility, 0, 228))
                crown_foam := canvas2d.Color{229, 251, 245, crown_alpha}
                crown_mist := canvas2d.Color{190, 235, 234, u8(f32(crown_alpha) * .78)}
                crown_clear := canvas2d.Color{crown_foam.r, crown_foam.g, crown_foam.b, 0}
                world_rondine_triangle_colored(root, foot, crest, crown_foam, crown_clear, crown_mist, crown_mirrored)
                crown_tip := crest + contact_right * (loaded_side * (.22 + prong_f * .16))
                crown_tip.y -= .12 + prong_f * .05
                world_rondine_triangle_colored(
                    foot,
                    crown_tip,
                    crest,
                    crown_clear,
                    crown_clear,
                    crown_foam,
                    crown_mirrored,
                )
            }

            // Fine bright needles run through the larger translucent crown.
            // They give the hero-scale sheet internal motion without another
            // filled fan or any sprite-facing orientation problem.
            for needle in 0 ..< 5 {
                needle_f := f32(needle)
                variation := world_rondine_live_variation(live_spray_epoch, live_spray_blend, 1, u32(30 + needle))
                position :=
                    stern +
                    contact_right * (loaded_side * (.58 + needle_f * .29)) +
                    contact_back * (.18 + needle_f * .34)
                position.y += .08 + needle_f * .07 + variation * .16
                direction :=
                    contact_back * (1.02 - needle_f * .24 + variation * .22) +
                    contact_right * (loaded_side * (.42 + needle_f * .46 + variation * .24)) +
                    third_person.Vec3{0, .34 + needle_f * .16 + variation * .34, 0}
                needle_alpha := u8(clamp((145 + variation * 70) * crown_visibility, 0, 215))
                needle_color := canvas2d.Color{232, 253, 247, needle_alpha}
                world_rondine_spray_streak(
                    camera,
                    position,
                    direction,
                    .25 + crown_strength * .22 + variation * .12,
                    needle_color,
                )
            }

            // A dense crown of detached splash heads softens the top edge of
            // the faceted curtain. Their staggered heights and positions turn
            // the five overlapping panels into one turbulent mass instead of
            // exposing a row of individual triangle tips.
            for splash in 0 ..< 8 {
                splash_f := f32(splash)
                variation := world_rondine_live_variation(live_spray_epoch, live_spray_blend, 1, u32(360 + splash))
                crown_progress := (splash_f + .35 + variation * .28) / 8
                crown_hump := f32(math.sin(f64(crown_progress * math.PI)))
                splash_position :=
                    stern +
                    contact_right * (loaded_side * (.92 + crown_progress * (3.35 + crown_strength * .90))) +
                    contact_back * (.52 + crown_progress * (3.20 + crown_strength * 1.35))
                splash_position.y += .52 + crown_hump * (1.18 + crown_strength * 2.40) + (variation - .5) * .34
                splash_direction :=
                    contact_back * (.34 + variation * .34) +
                    contact_right * (loaded_side * (.42 + crown_progress * .55)) +
                    third_person.Vec3{0, .38 + crown_hump * .62 + variation * .28, 0}
                splash_alpha := u8(clamp((178 + variation * 66) * crown_visibility, 0, 232))
                splash_color := canvas2d.Color{235, 254, 248, splash_alpha}
                world_rondine_spray_streak(
                    camera,
                    splash_position,
                    splash_direction,
                    .12 + variation * .13 + crown_strength * .08,
                    splash_color,
                )
                world_rondine_spray_bead(
                    camera,
                    splash_position + linalg.normalize0(splash_direction) * (.20 + variation * .14),
                    .040 + variation * .030 + crown_strength * .016,
                    splash_color,
                )
            }

            // A rapid breakaway gets its own radial snap, distinct from the
            // crown that persists through a sustained drift. The rays spread
            // across height and lateral angle, then vanish with drift_kick.
            if drift_kick > .08 {
                kick_root := stern + contact_right * (loaded_side * .72)
                for ray in 0 ..< 3 {
                    ray_f := f32(ray)
                    variation := world_rondine_live_variation(live_spray_epoch, live_spray_blend, 1, u32(60 + ray))
                    position :=
                        kick_root + contact_back * (ray_f * .18) + contact_right * (loaded_side * (ray_f - 1) * .18)
                    position.y += .08 + ray_f * .09 + variation * .11
                    direction :=
                        contact_back * (1.35 - ray_f * .50 + variation * .10) +
                        contact_right * (loaded_side * (.16 + ray_f * .74 + variation * .12)) +
                        third_person.Vec3{0, .24 + ray_f * .34 + variation * .18, 0}
                    kick_alpha := u8(clamp((168 + variation * 62) * drift_kick, 0, 225))
                    kick_color := canvas2d.Color{235, 254, 248, kick_alpha}
                    world_rondine_spray_streak(
                        camera,
                        position,
                        direction,
                        .76 + drift_kick * .64 + ray_f * .08 + variation * .14,
                        kick_color,
                    )
                }
            }
        }

        // When lateral grip hooks back up, two symmetric inward sprays cross
        // behind the stern. This is deliberately unlike the one-sided
        // breakaway fan: a brief visual "clap" as the hull straightens.
        if hookup_kick > .08 {
            for side in 0 ..< 2 {
                side_sign := side == 0 ? f32(-1) : f32(1)
                for ray in 0 ..< 2 {
                    ray_f := f32(ray)
                    variation := world_rondine_live_variation(
                        live_spray_epoch,
                        live_spray_blend,
                        u32(side),
                        u32(70 + ray),
                    )
                    position :=
                        stern + contact_right * (side_sign * (.62 + ray_f * .18)) + contact_back * (ray_f * .16)
                    position.y += .10 + variation * .12
                    direction :=
                        contact_back * (.72 + ray_f * .24 + variation * .14) +
                        contact_right * (-side_sign * (.44 + ray_f * .30 + variation * .12)) +
                        third_person.Vec3{0, .34 + ray_f * .20 + variation * .18, 0}
                    hookup_alpha := u8(clamp((150 + variation * 62) * hookup_kick, 0, 210))
                    hookup_color := canvas2d.Color{232, 253, 247, hookup_alpha}
                    world_rondine_spray_streak(
                        camera,
                        position,
                        direction,
                        .46 + hookup_kick * .48 + ray_f * .10,
                        hookup_color,
                    )
                }
            }
        }

        // Countersteer while the hull is still sliding cuts two low hooks
        // across the established wake. Keeping them close to the surface and
        // opposite the loaded spray makes this read as pilot correction,
        // distinct from both the tall breakaway crown and symmetric hookup.
        if countersteer > .06 {
            loaded_side := editor.rondine.telemetry.slip < 0 ? f32(-1) : f32(1)
            for cut in 0 ..< 3 {
                cut_f := f32(cut)
                variation := world_rondine_live_variation(live_spray_epoch, live_spray_blend, 1, u32(170 + cut))
                position :=
                    stern + contact_right * (loaded_side * (.48 + cut_f * .18)) + contact_back * (.12 + cut_f * .20)
                position.y += .055 + variation * .075
                direction :=
                    contact_back * (.48 + cut_f * .16 + variation * .12) -
                    contact_right * (loaded_side * (.58 + cut_f * .26 + variation * .16)) +
                    third_person.Vec3{0, .08 + cut_f * .045 + variation * .07, 0}
                cut_alpha := u8(clamp((126 + variation * 68) * countersteer, 0, 194))
                cut_color := canvas2d.Color{229, 252, 246, cut_alpha}
                world_rondine_spray_streak(
                    camera,
                    position,
                    direction,
                    .24 + countersteer * .24 + cut_f * .055,
                    cut_color,
                )
            }

            // A bright, low snap brace crosses the stern at the moment the
            // pilot steers back into the slide. Spray streaks communicate
            // motion but can vanish edge-on; paired surface chips make the
            // correction readable from chase and inspection cameras alike.
            counter_visibility := f32(math.sqrt(f64(countersteer)))
            brace_alpha := u8(clamp(198 * counter_visibility, 0, 202))
            brace_color := canvas2d.Color{233, 253, 247, brace_alpha}
            brace_tangent := contact_right * (-loaded_side * .92) + contact_back * .24
            brace_radial := contact_back + contact_right * (loaded_side * .14)
            for brace in 0 ..< 2 {
                brace_f := f32(brace)
                brace_position :=
                    stern +
                    contact_back * (.58 + brace_f * .26) +
                    contact_right * (loaded_side * (.18 - brace_f * .12))
                brace_position.y += .031
                world_rondine_surface_chip(
                    brace_position,
                    brace_tangent,
                    brace_radial,
                    .20 + counter_visibility * .16 - brace_f * .025,
                    .034 + counter_visibility * .018,
                    {brace_color.r, brace_color.g, brace_color.b, u8(f32(brace_alpha) * (1 - brace_f * .24))},
                    double_sided = true,
                )
            }

            // Countersteer briefly catches water on the side opposite the
            // established drift wall. One lower, shorter sheet makes that
            // pressure transfer readable at gameplay distance without
            // competing with the tall loaded-side crown.
            catch_side := -loaded_side
            catch_root := stern + contact_right * (catch_side * .46) + contact_back * .10
            catch_foot :=
                catch_root +
                contact_back * (1.04 + countersteer * .68) +
                contact_right * (catch_side * (.66 + countersteer * .58))
            catch_crest := (catch_root + catch_foot) * .5
            catch_crest += contact_right * (catch_side * (.13 + countersteer * .12))
            catch_crest.y += .42 + counter_visibility * 1.38
            catch_alpha := u8(clamp((168 + countersteer * 72) * counter_visibility, 0, 184))
            catch_foam := canvas2d.Color{228, 251, 245, catch_alpha}
            catch_mist := canvas2d.Color{176, 231, 232, u8(f32(catch_alpha) * .56)}
            catch_clear := canvas2d.Color{catch_foam.r, catch_foam.g, catch_foam.b, 0}
            world_rondine_triangle_double_sided(
                catch_root,
                catch_foot,
                catch_crest,
                catch_foam,
                catch_clear,
                catch_mist,
            )
            catch_tip := catch_crest + contact_right * (catch_side * (.16 + countersteer * .16)) + contact_back * .12
            catch_tip.y -= .09
            world_rondine_triangle_double_sided(
                catch_foot,
                catch_tip,
                catch_crest,
                catch_clear,
                catch_clear,
                catch_foam,
            )
            catch_ridge_direction :=
                contact_back * .44 + contact_right * (catch_side * .58) + third_person.Vec3{0, .12, 0}
            world_rondine_spray_streak(
                camera,
                catch_crest,
                catch_ridge_direction,
                .14 + countersteer * .18,
                {235, 254, 248, u8(clamp(188 * counter_visibility, 0, 194))},
            )
        }

        // A hard bank can bring the low wingtip close enough to rake the
        // surface. Derive clearance from hull skim height plus the wing's
        // vertical bank displacement; level planing keeps both tips safely
        // dormant, while an aggressive correction lights only the low side.
        wing_half_span := f32(4.65)
        wing_presentation_basis := world_rondine_presentation_basis(editor)
        loaded_wing_side := editor.rondine.telemetry.slip < 0 ? f32(-1) : f32(1)
        for side in 0 ..< 2 {
            side_sign := side == 0 ? f32(-1) : f32(1)
            if side_sign != loaded_wing_side do continue
            low_tip_displacement := max(-wing_presentation_basis.right.y * side_sign * wing_half_span, f32(0))
            // Lateral hull load compresses the loaded outboard skim even when
            // presentation heel is deliberately restrained for readability.
            // This lets a sustained slide rake one side while level, no-slip
            // planing remains exactly dormant.
            loaded_tip_compression := f32(0)
            if side_sign == loaded_wing_side {
                loaded_tip_compression = math.abs(editor.rondine.telemetry.slip) * .72 + drift_strength * .10
            }
            tip_proximity := clamp((max(low_tip_displacement, loaded_tip_compression) - .10) / .62, 0, 1)
            tip_strength :=
                tip_proximity * clamp(contact_strength * .62 + drift_strength * .58 + countersteer * .34, 0, 1)
            if tip_strength <= .045 do continue
            tip_visibility := f32(math.sqrt(f64(tip_strength)))
            tip_root := contact_base + contact_right * (side_sign * (wing_half_span + .28)) + contact_back * .62
            tip_root.y += .045
            // The original rake streaks supplied motion but disappeared at
            // chase distance. A translucent triangular sheet gives the skim a
            // large-scale silhouette while keeping its root pinned outside
            // the propwash footprint.
            tip_sheet_foot :=
                tip_root +
                contact_back * (1.18 + tip_strength * .82) +
                contact_right * (side_sign * (.38 + tip_strength * .34))
            tip_sheet_crest := (tip_root + tip_sheet_foot) * .5
            tip_sheet_crest += contact_right * (side_sign * (.48 + tip_strength * .48))
            tip_sheet_crest.y += .58 + tip_strength * 1.80
            tip_sheet_alpha := u8(clamp(205 * tip_visibility, 0, 214))
            tip_sheet_foam := canvas2d.Color{226, 251, 245, tip_sheet_alpha}
            tip_sheet_mist := canvas2d.Color{148, 220, 227, u8(f32(tip_sheet_alpha) * .48)}
            tip_sheet_clear := canvas2d.Color{tip_sheet_foam.r, tip_sheet_foam.g, tip_sheet_foam.b, 0}
            for tip_panel in 0 ..< 3 {
                panel_start := f32(tip_panel) / 3
                panel_end := f32(tip_panel + 1) / 3
                lower_start := tip_root + (tip_sheet_foot - tip_root) * panel_start
                lower_end := tip_root + (tip_sheet_foot - tip_root) * panel_end
                start_hump := f32(math.sin(f64(panel_start * math.PI)))
                end_hump := f32(math.sin(f64(panel_end * math.PI)))
                upper_start := lower_start + (tip_sheet_crest - lower_start) * (start_hump * .92)
                upper_end := lower_end + (tip_sheet_crest - lower_end) * (end_hump * .92)
                world_rondine_triangle_double_sided(
                    lower_start,
                    lower_end,
                    upper_end,
                    tip_sheet_clear,
                    tip_sheet_clear,
                    tip_sheet_mist,
                )
                world_rondine_triangle_double_sided(
                    lower_start,
                    upper_end,
                    upper_start,
                    tip_sheet_clear,
                    tip_sheet_mist,
                    tip_sheet_foam,
                )
            }
            for rake in 0 ..< 2 {
                rake_f := f32(rake)
                variation := world_rondine_live_variation(
                    live_spray_epoch,
                    live_spray_blend,
                    u32(side),
                    u32(310 + rake),
                )
                position :=
                    tip_root + contact_back * (rake_f * .16) + contact_right * (side_sign * (variation - .5) * .10)
                direction :=
                    contact_back * (.78 + rake_f * .24 + variation * .22) +
                    contact_right * (side_sign * (.20 + rake_f * .24 + variation * .16)) +
                    third_person.Vec3{0, .24 + rake_f * .18 + variation * .24, 0}
                rake_alpha := u8(clamp((154 + variation * 64 - rake_f * 18) * tip_visibility, 0, 212))
                rake_color := canvas2d.Color{233, 253, 247, rake_alpha}
                world_rondine_spray_streak(
                    camera,
                    position,
                    direction,
                    .48 + tip_strength * .66 + rake_f * .12,
                    rake_color,
                )
                bead_position := position + linalg.normalize0(direction) * (.62 + tip_strength * .38 + rake_f * .14)
                world_rondine_spray_bead(
                    camera,
                    bead_position,
                    .045 + tip_visibility * .030 + rake_f * .006,
                    {235, 254, 248, u8(f32(rake_alpha) * .78)},
                )
            }
            crown_bead_position := tip_sheet_crest + contact_right * (side_sign * .16)
            crown_bead_position.y += .10
            world_rondine_spray_bead(
                camera,
                crown_bead_position,
                .052 + tip_visibility * .038,
                {235, 254, 248, u8(f32(tip_sheet_alpha) * .86)},
            )
            // A short diagonal scar anchors the airborne rake to the water.
            // It sits outside the propwash footprint, so the player can read
            // that the wing—not the engine—touched the surface.
            scrawl_tangent := contact_back * .78 + contact_right * (side_sign * .36)
            scrawl_radial := contact_right * side_sign - contact_back * .18
            scrawl_alpha := u8(clamp(188 * tip_visibility, 0, 194))
            world_rondine_surface_chip(
                tip_root + contact_back * .16,
                scrawl_tangent,
                scrawl_radial,
                .22 + tip_strength * .20,
                .032 + tip_strength * .020,
                {230, 252, 246, scrawl_alpha},
                double_sided = true,
            )
        }

        // The pusher propellers sit well outside the hull. Their downwash
        // strikes the surface as a second, narrower pair of spray sheets,
        // visually tying the wake to Rondine's full span instead of making all
        // of the water energy appear to originate at the centerline.
        // A sliding Rondine loads the wide pusher contact points even when the
        // generic hull-contact spray has already settled. Feeding drift
        // directly into prop wash keeps the live effect spanning the aircraft
        // instead of collapsing into a faint centerline wake during a stable
        // Tokyo-drift-style slide.
        propwash_strength := clamp(contact_strength * (.52 + drift_strength * .38) + drift_strength * .34, 0, 1.15)
        if propwash_strength > .08 {
            for side in 0 ..< 2 {
                side_sign := side == 0 ? f32(-1) : f32(1)
                outside := clamp(1 + side_sign * editor.rondine.telemetry.slip * 1.25, .55, 1.45)
                root := contact_base + contact_right * (side_sign * 3.8) + body_back * .35
                heel_offset := editor.rondine.telemetry.slip * drift_strength * 1.25
                foot :=
                    root +
                    contact_back * (1.2 + propwash_strength * 1.8) +
                    contact_right * (side_sign * (.18 + propwash_strength * .42) + heel_offset)
                crest := root + contact_back * (.55 + propwash_strength * .9) + contact_right * (side_sign * .12)
                crest.y += .25 + propwash_strength * 1.20 * outside
                edge := foot + contact_right * (side_sign * (.22 + propwash_strength * .38) * outside)
                prop_alpha := u8(clamp(172 * propwash_strength * outside, 0, 214))
                prop_foam := canvas2d.Color{224, 249, 243, prop_alpha}
                prop_mist := canvas2d.Color{143, 217, 224, u8(f32(prop_alpha) * .48)}
                prop_clear := canvas2d.Color{prop_foam.r, prop_foam.g, prop_foam.b, 0}
                world_rondine_triangle_colored(root, foot, crest, prop_foam, prop_foam, prop_mist, side == 1)
                world_rondine_triangle_colored(foot, edge, crest, prop_foam, prop_clear, prop_mist, side == 1)

                // Low, bright prop-bite chips remain legible when the taller
                // translucent sheet is edge-on to the chase camera. Their
                // staggered placement also shows the prop contact sweeping
                // rearward rather than appearing as a static point under the
                // wing.
                bite_alpha := u8(clamp(172 * propwash_strength * outside, 0, 205))
                bite_color := canvas2d.Color{229, 252, 246, bite_alpha}
                for bite in 0 ..< 2 {
                    bite_f := f32(bite)
                    bite_position :=
                        root +
                        contact_back * (.42 + bite_f * .38) +
                        contact_right * (side_sign * (.08 + bite_f * .09 + heel_offset * .12))
                    bite_position.y += .025
                    bite_tangent :=
                        contact_back * (.78 + bite_f * .14) + contact_right * (side_sign * (.26 + outside * .12))
                    bite_radial := contact_right * side_sign - contact_back * (.08 + bite_f * .05)
                    world_rondine_surface_chip(
                        bite_position,
                        bite_tangent,
                        bite_radial,
                        .14 + propwash_strength * .10 - bite_f * .018,
                        .028 + propwash_strength * .014,
                        {bite_color.r, bite_color.g, bite_color.b, u8(f32(bite_alpha) * (1 - bite_f * .24))},
                    )
                }

                // Each pusher contact flicks off two narrow filaments. The
                // loaded prop gets longer, brighter trajectories while the
                // unloaded side remains a quieter positional cue.
                pressure_role := outside >= 1 ? u32(1) : u32(0)
                for filament in 0 ..< 2 {
                    filament_f := f32(filament)
                    variation := world_rondine_live_variation(
                        live_spray_epoch,
                        live_spray_blend,
                        pressure_role,
                        u32(50 + side * 2 + filament),
                    )
                    prop_phase := math.sin(
                        (editor.rondine.propeller_turns + f32(side) * .5 + filament_f * .19) * math.TAU,
                    )
                    filament_position :=
                        root +
                        contact_back * (.68 + filament_f * .46) +
                        contact_right * (side_sign * (.10 + filament_f * .18 + prop_phase * .07))
                    filament_position.y += .18 + variation * .24 + prop_phase * .055
                    filament_direction :=
                        contact_back * (.54 + variation * .32) +
                        contact_right * (side_sign * (.68 + filament_f * .38 + variation * .26 + prop_phase * .12)) +
                        third_person.Vec3{0, .36 + filament_f * .22 + variation * .34 + prop_phase * .10, 0}
                    filament_alpha := u8(clamp((105 + variation * 62) * propwash_strength * outside, 0, 195))
                    filament_color := canvas2d.Color{229, 252, 246, filament_alpha}
                    world_rondine_spray_streak(
                        camera,
                        filament_position,
                        filament_direction,
                        (.42 + variation * .20 + filament_f * .10) * outside * (1 + prop_phase * .10),
                        filament_color,
                    )
                }
            }
        }

    }
}
