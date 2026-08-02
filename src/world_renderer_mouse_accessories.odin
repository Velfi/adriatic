package main

import third_person "../packages/third_person"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

Mouse_Accessory_Render_Context :: struct {
    using render:                                                    Mouse_Render_Context,
    head_y, head_z, head_sway, head_turn_x, body_roll, blink_weight: f32,
    features, leather, leather_dark, goggle_glass, brass:            canvas2d.Color,
}

world_mouse_accessory :: proc(ctx: Mouse_Accessory_Render_Context) {
    editor, model, p, rotation := ctx.editor, ctx.model, ctx.p, ctx.rotation
    model_forward := ctx.model_forward
    head_y, head_z, head_sway := ctx.head_y, ctx.head_z, ctx.head_sway
    head_turn_x, body_roll, blink_weight := ctx.head_turn_x, ctx.body_roll, ctx.blink_weight
    fur, features, ear, leather, leather_dark, goggle_glass :=
        ctx.fur, ctx.features, ctx.ear, ctx.leather, ctx.leather_dark, ctx.goggle_glass
    tooth, brass := ctx.tooth, ctx.brass
    @(no_instrumentation)
    local_point :: #force_inline proc(origin: third_person.Vec3, yaw, x, y, z: f32) -> third_person.Vec3 {
        world_x, world_z := world_rotate_xz(origin.x, origin.z, x, z, yaw)
        return {world_x, origin.y + y, world_z}
    }
    if model.accessory == .Goggles {
        // The goggles rest above the eyes so the face stays expressive. Every
        // component follows head sway and the spine-driven running reach.
        goggle_y := head_y + .112
        goggle_z := head_z + .31
        goggle_roll_slope := math.sin(body_roll) * .32
        goggle_strap_left := local_point(
            p,
            rotation,
            -.25 + head_sway + head_turn_x,
            goggle_y - .25 * goggle_roll_slope,
            head_z + .285,
        )
        goggle_strap_right := local_point(
            p,
            rotation,
            .25 + head_sway + head_turn_x,
            goggle_y + .25 * goggle_roll_slope,
            head_z + .285,
        )
        world_box_between(goggle_strap_left, goggle_strap_right, model_forward, .032, .022, leather_dark)
        // Keep each cup tight to its side of the skull. At a true profile the
        // former broad, deeply canted far cup projected beyond the muzzle and
        // looked as though it rendered through the head.
        goggle_offsets := [2]f32{-.18, .18}
        for goggle_x in goggle_offsets {
            goggle_side := goggle_x / .18
            // The two cups follow the curved brow rather than sharing one
            // billboard plane. A restrained outward cant keeps the near lens
            // readable in profile while preserving their forward function.
            goggle_cant := f32(.85)
            goggle_rotation := rotation - goggle_side * goggle_cant
            goggle_normal_x := goggle_side * f32(math.sin(f64(goggle_cant)))
            goggle_normal_z := f32(math.cos(f64(goggle_cant)))
            world_vertical_disc_rotated(
                local_point(
                    p,
                    rotation,
                    goggle_x + head_sway + head_turn_x,
                    goggle_y + goggle_x * goggle_roll_slope,
                    goggle_z,
                ),
                .050,
                .042,
                .022,
                goggle_rotation,
                leather,
            )
            world_vertical_disc_rotated(
                local_point(
                    p,
                    rotation,
                    goggle_x + goggle_normal_x * .020 + head_sway + head_turn_x,
                    goggle_y + goggle_x * goggle_roll_slope,
                    goggle_z + goggle_normal_z * .020,
                ),
                .036,
                .028,
                .010,
                goggle_rotation,
                goggle_glass,
            )
            world_vertical_disc_rotated(
                local_point(
                    p,
                    rotation,
                    goggle_x + goggle_normal_x * .030 - goggle_side * .009 + head_sway + head_turn_x,
                    goggle_y + .010 + goggle_x * goggle_roll_slope,
                    goggle_z + goggle_normal_z * .030,
                ),
                .008,
                .008,
                .005,
                goggle_rotation,
                tooth,
            )

            // Curved side shields keep the headset identifiable when the
            // camera reaches a true profile. They share the cup's material and
            // glass, so this reads as wraparound goggles rather than a badge.
            side_window_rotation := rotation - goggle_side * (math.PI * .5)
            side_window_x := goggle_x + goggle_side * .035 + head_sway + head_turn_x
            side_window_y := goggle_y + goggle_x * goggle_roll_slope
            side_window_z := goggle_z - .008
            world_vertical_disc_rotated(
                local_point(p, rotation, side_window_x, side_window_y, side_window_z),
                .024,
                .021,
                .008,
                side_window_rotation,
                leather,
            )
            world_vertical_disc_rotated(
                local_point(p, rotation, side_window_x + goggle_side * .010, side_window_y, side_window_z),
                .017,
                .014,
                .005,
                side_window_rotation,
                goggle_glass,
            )
        }
        bridge_left := local_point(
            p,
            rotation,
            -.083 + head_sway + head_turn_x,
            goggle_y - .083 * goggle_roll_slope,
            goggle_z + .015,
        )
        bridge_right := local_point(
            p,
            rotation,
            .083 + head_sway + head_turn_x,
            goggle_y + .083 * goggle_roll_slope,
            goggle_z + .015,
        )
        world_box_between(bridge_left, bridge_right, model_forward, .018, .018, brass)
        // Side straps keep the goggles legible in profile and describe how the
        // frames actually wrap around the skull instead of hovering over it.
        strap_sides := [2]f32{-1, 1}
        for strap_side in strap_sides {
            strap_front := local_point(
                p,
                rotation,
                strap_side * .195 + head_sway + head_turn_x,
                goggle_y - .004,
                goggle_z - .018,
            )
            strap_crown := local_point(
                p,
                rotation,
                strap_side * .21 + head_sway + head_turn_x,
                head_y + .105,
                head_z + .17,
            )
            strap_back := local_point(
                p,
                rotation,
                strap_side * .18 + head_sway + head_turn_x,
                head_y + .065,
                head_z - .015,
            )
            world_box_between(strap_front, strap_crown, model_forward, .018, .012, leather_dark)
            world_box_between(strap_crown, strap_back, model_forward, .018, .012, leather_dark)
        }
    } else if model.accessory == .Flower {
        // Keep the flower tucked beside one ear, but cant the whole bloom
        // outward so its petal plane clears the head instead of cutting
        // through it.
        flower_side := model.accessory_side
        if flower_side == 0 do flower_side = -1
        flower_side = flower_side < 0 ? f32(-1) : f32(1)
        flower_center_x := flower_side * .115 + head_sway + head_turn_x
        flower_center_y := head_y + .205
        flower_center_z := head_z + .095
        flower_cant := flower_side * -.95
        flower_yaw := rotation + flower_cant
        flower_plane_x := math.cos(flower_cant)
        flower_plane_z := math.sin(flower_cant)
        stem_bottom := local_point(
            p,
            rotation,
            flower_center_x - flower_side * .045,
            head_y + .105,
            flower_center_z - .025,
        )
        stem_top := local_point(p, rotation, flower_center_x, flower_center_y, flower_center_z)
        world_box_between(stem_bottom, stem_top, model_forward, .018, .012, {70, 123, 72, 255})
        petal_color: canvas2d.Color = {238, 111, 137, 255}
        for petal_index in 0 ..< 5 {
            petal_angle := f32(petal_index) * math.PI * 2 / 5 + math.PI * .5
            petal_across := math.cos(petal_angle) * .052
            petal_x := flower_center_x + petal_across * flower_plane_x
            petal_y := flower_center_y + math.sin(petal_angle) * .052
            petal_z := flower_center_z + petal_across * flower_plane_z
            world_vertical_disc_rotated(
                local_point(p, rotation, petal_x, petal_y, petal_z),
                .044,
                .057,
                .018,
                flower_yaw,
                petal_color,
                .Petal,
            )
        }
        world_vertical_disc_rotated(
            local_point(
                p,
                rotation,
                flower_center_x - math.sin(flower_cant) * .014,
                flower_center_y,
                flower_center_z + math.cos(flower_cant) * .014,
            ),
            .033,
            .033,
            .018,
            flower_yaw,
            {232, 180, 62, 255},
        )
    } else if model.accessory == .Acorn_Cap {
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .135
        crown_z := head_z + .105
        shell := canvas2d.Color{105, 69, 39, 255}
        shell_dark := canvas2d.Color{67, 43, 27, 255}
        // Keep the fitted edge inside the crown silhouette. A broad lower
        // flange reads as a brim; an acorn cup instead pinches gently around
        // the head and swells into a taller woody dome.
        world_ellipsoid_rotated(
            local_point(p, rotation, crown_x, crown_y - .002, crown_z),
            .202,
            .026,
            .188,
            rotation,
            color_lerp(shell_dark, shell, .62),
        )
        world_ellipsoid_rotated(
            local_point(p, rotation, crown_x, crown_y + .040, crown_z),
            .218,
            .115,
            .203,
            rotation,
            shell,
            .Acorn,
        )
        stem_bottom := local_point(p, rotation, crown_x + .018, crown_y + .150, crown_z - .022)
        stem_top := local_point(p, rotation, crown_x + .045, crown_y + .210, crown_z - .080)
        world_box_between(stem_bottom, stem_top, model_forward, .020, .018, shell_dark)
    } else if model.accessory == .Bottle_Cap {
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .205
        crown_z := head_z + .105
        cap := canvas2d.Color{184, 39, 45, 255}
        world_bottle_cap_hull(local_point(p, rotation, crown_x, crown_y - .013, crown_z), rotation, cap)
    } else if model.accessory == .Paper_Boat {
        paper := canvas2d.Color{232, 224, 198, 255}
        paper_shadow := canvas2d.Color{190, 180, 157, 255}
        paper_light := canvas2d.Color{248, 241, 216, 255}
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .220
        crown_z := head_z + .105
        front_z := crown_z + .115
        back_z := crown_z - .085
        left_front := local_point(p, rotation, crown_x - .135, crown_y + .005, front_z)
        right_front := local_point(p, rotation, crown_x + .135, crown_y + .005, front_z)
        keel_front := local_point(p, rotation, crown_x, crown_y - .055, front_z)
        peak_front := local_point(p, rotation, crown_x - .018, crown_y + .115, front_z)
        left_back := local_point(p, rotation, crown_x - .135, crown_y + .005, back_z)
        right_back := local_point(p, rotation, crown_x + .135, crown_y + .005, back_z)
        keel_back := local_point(p, rotation, crown_x, crown_y - .055, back_z)
        peak_back := local_point(p, rotation, crown_x - .018, crown_y + .115, back_z)

        // True folded triangular panels replace the former yawed boxes, which
        // looked like a propeller because they never rose into a boat profile.
        world_triangle(left_front, keel_front, peak_front, paper)
        world_triangle(keel_front, right_front, peak_front, paper_light)
        world_triangle(peak_back, keel_back, left_back, paper_shadow)
        world_triangle(peak_back, right_back, keel_back, paper)
        world_quad(left_back, left_front, peak_front, peak_back, paper_shadow)
        world_quad(peak_back, peak_front, right_front, right_back, paper_light)
        world_quad(left_front, left_back, keel_back, keel_front, paper_shadow)
        world_quad(keel_front, keel_back, right_back, right_front, paper)

        // A broad tapered hull separates the boat silhouette from the much
        // narrower raised fold, avoiding the profile of a conical hat.
        world_tapered_box_rotated(
            local_point(p, rotation, crown_x, crown_y - .042, crown_z),
            .095,
            .380,
            .165,
            .535,
            .205,
            rotation,
            paper,
        )
        // Contrasting gunwale and central crease remain readable when the
        // mouse occupies only a small portion of the frame.
        world_box_rotated(
            local_point(p, rotation, crown_x, crown_y + .004, crown_z + .122),
            {.525, .022, .026},
            rotation,
            paper_light,
        )
        world_box_rotated(
            local_point(p, rotation, crown_x - .018, crown_y + .038, crown_z + .128),
            {.016, .145, .018},
            rotation,
            paper_shadow,
        )
    } else if model.accessory == .Chef_Hat {
        cloth := canvas2d.Color{226, 224, 211, 255}
        cloth_shadow := canvas2d.Color{174, 174, 168, 255}
        cloth_light := canvas2d.Color{244, 241, 224, 255}
        crown_x := head_sway + head_turn_x
        crown_z := head_z + .085
        // The double band hugs the skull and visually anchors the toque.
        world_box_rotated(
            local_point(p, rotation, crown_x, head_y + .190, crown_z),
            {.205, .060, .180},
            rotation,
            cloth_shadow,
        )
        world_box_rotated(
            local_point(p, rotation, crown_x, head_y + .218, crown_z + .010),
            {.190, .046, .172},
            rotation,
            cloth,
        )
        // Five overlapping matte lobes form one soft asymmetric crown without
        // the glossy eye material's bulb-like white highlights.
        puff_offsets := [5]f32{-.145, -.072, 0, .078, .150}
        for puff_x in puff_offsets {
            side := puff_x / .150
            world_ellipsoid_matte_rotated(
                local_point(
                    p,
                    rotation,
                    crown_x + puff_x,
                    head_y + .305 + (1 - math.abs(side)) * .020 + side * .008,
                    crown_z - math.abs(side) * .014,
                ),
                .105,
                .118 + (1 - math.abs(side)) * .020,
                .125,
                rotation,
                side < -.25 ? cloth_shadow : (side > .45 ? cloth_light : cloth),
            )
        }
        // A shallow crown seam adds a tailored center without competing with
        // the scalloped outline.
        world_box_rotated(
            local_point(p, rotation, crown_x, head_y + .355, crown_z + .135),
            {.010, .090, .024},
            rotation,
            cloth_shadow,
        )
    } else if model.accessory == .Ushanka {
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .150
        crown_z := head_z + .075
        wool := canvas2d.Color{101, 72, 55, 255}
        wool_dark := canvas2d.Color{58, 41, 34, 255}
        fur_trim := canvas2d.Color{181, 153, 119, 255}
        fur_shadow := canvas2d.Color{137, 111, 86, 255}
        ushanka_fur_light := canvas2d.Color{207, 184, 149, 255}

        // One radial hull replaces the former capped side-to-side extrusion.
        // Five horizontal rings round the crown in every camera direction.
        // The lowest two rings deform downward only near local +/-X, growing
        // both ear flaps directly from the same continuous surface.
        RINGS :: 7
        SEGMENTS :: 24
        ring_y := [RINGS]f32{.145, .105, .070, .040, .010, -.020, -.045}
        ring_radius_x := [RINGS]f32{.135, .190, .215, .230, .245, .240, .225}
        ring_radius_z := [RINGS]f32{.105, .145, .170, .185, .205, .210, .205}
        hull: [RINGS][SEGMENTS]third_person.Vec3
        side_weights: [SEGMENTS]f32
        front_weights: [SEGMENTS]f32
        for ring in 0 ..< RINGS {
            for segment in 0 ..< SEGMENTS {
                angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
                cosine, sine := math.cos(angle), math.sin(angle)
                side_weight := math.abs(cosine)
                side_weight *= side_weight
                front_weight := max(sine, f32(0))
                side_weights[segment] = side_weight
                front_weights[segment] = front_weight
                flap_drop := f32(0)
                if ring == RINGS - 4 do flap_drop = side_weight * .025
                if ring == RINGS - 3 do flap_drop = side_weight * .055
                if ring == RINGS - 2 do flap_drop = side_weight * .100
                if ring == RINGS - 1 {
                    // Hold the hem near full depth across a broad side arc
                    // instead of converging to one low vertex in profile.
                    // Alternate vertices retain a subtle fur scallop.
                    flap_span := clamp(math.abs(cosine) / .72, 0, 1)
                    tuft_drop := f32(0)
                    if segment % 5 == 0 {
                        tuft_drop = .012
                    } else if segment % 5 == 3 {
                        tuft_drop = .006
                    }
                    flap_drop = flap_span * (.160 + tuft_drop)
                }
                radius_x := ring_radius_x[ring]
                radius_z := ring_radius_z[ring]
                tuft_out := f32(.002)
                if segment % 5 == 0 {
                    tuft_out = .008
                } else if segment % 5 == 2 {
                    tuft_out = -.004
                }
                if ring >= RINGS - 4 && side_weight > .24 {
                    radius_x += tuft_out * side_weight
                    radius_z += tuft_out * side_weight
                }
                if ring >= 2 && ring <= 4 && front_weight > .35 {
                    radius_z += tuft_out * front_weight
                }
                // The traditional raised forehead flap is part of this same
                // surface: push only its central front vertices outward and
                // ease the displacement to zero before the temples.
                if ring >= 2 && ring <= 4 && front_weight > .55 {
                    panel_weight := (front_weight - .55) / .45
                    panel_depth := ring == 2 ? f32(.018) : (ring == 3 ? f32(.026) : f32(.016))
                    radius_z += panel_weight * panel_depth
                }
                hull[ring][segment] = local_point(
                    p,
                    rotation,
                    crown_x + cosine * radius_x,
                    crown_y + ring_y[ring] - flap_drop,
                    crown_z + sine * radius_z,
                )
            }
        }

        crown_top := local_point(p, rotation, crown_x, crown_y + .160, crown_z - .005)
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            top_color := front_weights[segment] > .25 ? wool : wool_dark
            // Angle increases from +X toward +Z, so the top fan must visit
            // the next rim vertex first to keep its outward face CCW.
            world_triangle(crown_top, hull[0][next], hull[0][segment], top_color)
        }
        for ring in 0 ..< RINGS - 1 {
            for segment in 0 ..< SEGMENTS {
                next := (segment + 1) % SEGMENTS
                front_weight := max(front_weights[segment], front_weights[next])
                side_weight := max(side_weights[segment], side_weights[next])
                surface_color := front_weight > .05 ? wool : wool_dark
                fur_variant := (segment * 5 + ring * 3) % 7
                // A narrow raised-looking fur brow and the two lined flaps are
                // material regions of the hull itself, not overlaid geometry.
                if (ring == 2 || ring == 3) && front_weight > .62 {
                    surface_color = fur_variant == 0 ? ushanka_fur_light : (fur_variant == 2 ? fur_shadow : fur_trim)
                } else if ring >= 3 && side_weight > .28 {
                    surface_color = fur_variant == 0 ? ushanka_fur_light : (fur_variant < 3 ? fur_shadow : fur_trim)
                } else if ring == 2 && side_weight > .45 {
                    // A cloth welt makes the flap attachment look sewn into
                    // the crown rather than painted onto the same surface.
                    surface_color = wool_dark
                } else if ring >= RINGS - 2 {
                    surface_color = wool_dark
                }
                world_quad(
                    hull[ring][segment],
                    hull[ring][next],
                    hull[ring + 1][next],
                    hull[ring + 1][segment],
                    surface_color,
                )
            }
        }
        // Close the underside so this remains one watertight hull. The cap is
        // tucked into the skull and normally invisible.
        hull_bottom := local_point(p, rotation, crown_x, crown_y - .058, crown_z)
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            // The underside uses the opposite rim order from the top fan so
            // its outward (downward) face remains CCW as well.
            world_triangle(hull_bottom, hull[RINGS - 1][segment], hull[RINGS - 1][next], wool_dark)
        }
    } else if model.accessory == .Beret {
        // Seat the band on the rear crown of the skull, just behind the ears.
        // The head's local +Z points toward the muzzle, so a small negative
        // depth offset is essential: centering this over the brow makes the
        // hat float above the ear in profile and read like a visor in front.
        crown_x := head_sway + head_turn_x - .020
        crown_y := head_y + .195
        crown_z := head_z + .015
        felt := canvas2d.Color{133, 38, 49, 255}
        felt_fold := canvas2d.Color{112, 31, 43, 255}
        felt_dark := canvas2d.Color{77, 26, 35, 255}
        felt_light := canvas2d.Color{178, 64, 70, 255}
        // Preserve the deliberate jaunty cock while inheriting most of the
        // animated head roll, so the band stays planted through turns and
        // uneven-ground poses instead of remaining level in world space.
        beret_roll := f32(.15) + body_roll * .65

        // A close-fitting oval band seats the beret on the skull. Keeping this
        // rounded avoids the rigid shelf and dangling corner of a box brim.
        world_ellipsoid_matte_oriented(
            local_point(p, rotation, crown_x + .010, crown_y - .006, crown_z - .004),
            .202,
            .026,
            .168,
            rotation,
            beret_roll,
            felt_dark,
        )
        // The crown leans to the mouse's left: a broad main disk establishes
        // the silhouette while the overlapping lobe makes the drape feel soft.
        world_ellipsoid_matte_oriented(
            local_point(p, rotation, crown_x - .045, crown_y + .036, crown_z - .004),
            .276,
            .073,
            .222,
            rotation,
            beret_roll,
            felt,
        )
        world_ellipsoid_matte_oriented(
            local_point(p, rotation, crown_x - .142, crown_y + .016, crown_z - .002),
            .145,
            .058,
            .160,
            rotation,
            beret_roll,
            felt_fold,
        )
        // A restrained highlight follows the upper fold instead of reading as
        // a separate cap sitting on top.
        world_ellipsoid_matte_oriented(
            local_point(p, rotation, crown_x - .105, crown_y + .086, crown_z + .025),
            .138,
            .025,
            .110,
            rotation,
            beret_roll,
            felt_light,
        )
        // The short cabillou follows the rolled crown normal instead of
        // remaining conspicuously vertical after the rest of the hat cocks.
        cabillou_root := local_point(p, rotation, crown_x - .070, crown_y + .108, crown_z - .018)
        cabillou_tip := local_point(
            p,
            rotation,
            crown_x - .070 - math.sin(beret_roll) * .042,
            crown_y + .108 + math.cos(beret_roll) * .042,
            crown_z - .018,
        )
        world_box_between(cabillou_root, cabillou_tip, model_forward, .014, .014, felt_dark)
    } else if model.accessory == .Alpine_Hat {
        crown_x := head_sway + head_turn_x
        // Seat the brim into the crown of the head instead of perching the
        // whole assembly above the ears.
        crown_y := head_y + .155
        crown_z := head_z + .070
        felt := canvas2d.Color{67, 105, 71, 255}
        felt_dark := canvas2d.Color{38, 69, 48, 255}
        felt_light := canvas2d.Color{91, 125, 86, 255}
        band := canvas2d.Color{103, 61, 39, 255}
        band_light := canvas2d.Color{143, 91, 54, 255}
        feather := canvas2d.Color{190, 58, 43, 255}
        feather_light := canvas2d.Color{224, 86, 54, 255}

        // Brim, crown, shoulder, and top are one continuous closed felt shell.
        // The profile contracts and shifts rearward as it rises, producing the
        // characteristic Alpine taper without stacked primitive intersections.
        world_alpine_hat_hull(
            local_point(p, rotation, crown_x, crown_y - .015, crown_z + .005),
            rotation,
            felt_dark,
            felt,
            felt_light,
        )

        // Build the hatband as an oval collar so it remains continuous in
        // front and three-quarter views. The small buckle gives it a focal
        // point without obscuring the face.
        world_ellipsoid_matte_rotated(
            local_point(p, rotation, crown_x, crown_y + .005, crown_z),
            .250,
            .038,
            .201,
            rotation,
            band,
        )
        world_box_rotated(
            local_point(p, rotation, crown_x + .135, crown_y + .010, crown_z + .172),
            {.055, .066, .018},
            rotation,
            band_light,
        )
        // Continue the band along the feather side. The oval collar supplies
        // the curved lower edge; this shallow strip keeps the leather legible
        // in profile instead of collapsing to a small brown diamond.
        world_box_rotated(
            local_point(p, rotation, crown_x + .218, crown_y + .010, crown_z),
            {.028, .058, .285},
            rotation,
            band,
        )

        // The plume is a single smooth vane with its broad face in the hat's
        // side plane. This avoids both a twig-like front view and the blocky
        // stepped profile produced by assembled vane segments.
        feather_base := local_point(p, rotation, crown_x + .155, crown_y + .030, crown_z + .145)
        feather_tip := local_point(p, rotation, crown_x + .280, crown_y + .365, crown_z + .108)
        world_alpine_feather_hull(
            local_point(p, rotation, crown_x + .225, crown_y + .205, crown_z + .122),
            rotation,
            feather,
            feather_light,
        )
        world_box_between(feather_base, feather_tip, model_forward, .012, .020, feather)
    } else if model.accessory == .Flat_Cap {
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .155
        crown_z := head_z + .070
        tweed := canvas2d.Color{118, 103, 82, 255}
        tweed_dark := canvas2d.Color{62, 54, 46, 255}
        tweed_light := canvas2d.Color{137, 120, 94, 255}
        tweed_front := canvas2d.Color{126, 110, 87, 255}

        world_flat_cap_hull(
            local_point(p, rotation, crown_x, crown_y, crown_z),
            rotation,
            tweed_dark,
            tweed,
            tweed_front,
            tweed_light,
        )
    } else if model.accessory == .Sailor_Hat {
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .145
        crown_z := head_z + .065
        canvas := canvas2d.Color{242, 239, 221, 255}
        world_sailor_hat_hull(local_point(p, rotation, crown_x, crown_y, crown_z), rotation, canvas)
    }

}
