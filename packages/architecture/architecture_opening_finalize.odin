package architecture

import buildings "../buildings"
import "core:math"

architecture_opening_layout_finalize :: proc(layout: ^Opening_Layout, ctx: Architecture_Opening_Face_Context) {
    structure := ctx.structure
    footprint := ctx.footprint
    mass := ctx.mass
    identity := ctx.identity
    profile := ctx.profile
    wall_height := ctx.wall_height
    mass_index := ctx.mass_index
    farmstead_work_range := ctx.farmstead_work_range
    shop_stock_range := ctx.shop_stock_range
    post_sorting_range := ctx.post_sorting_range
    clinic_ward_range := ctx.clinic_ward_range
    fortress_tower := ctx.fortress_tower
    fortress_guard_range := ctx.fortress_guard_range
    bell_tower := ctx.bell_tower
    mill_tower := ctx.mill_tower
    barn_range := ctx.barn_range
    workshop_daylight := ctx.workshop_daylight
    fishery_work_hall := ctx.fishery_work_hall
    storehouse_high_vents := ctx.storehouse_high_vents
    harbor_dispatch_range := ctx.harbor_dispatch_range
    harbor_service_range := ctx.harbor_service_range
    habitable := ctx.habitable
    occupied_secondary_daylight := ctx.occupied_secondary_daylight
    storehouse_loading_range := ctx.storehouse_loading_range
    fishery_smokehouse_range := ctx.fishery_smokehouse_range
    market_loading_range := ctx.market_loading_range
    market_basilica_aisle := ctx.market_basilica_aisle
    market_basilica_nave := ctx.market_basilica_nave
    monastery_cloister_range := ctx.monastery_cloister_range
    primary_mass := ctx.primary_mass
    mixed_use_apartment_face := ctx.mixed_use_apartment_face
    faces := [4]Face{.Front, .Rear, .Left, .Right}


    if mill_tower {
        // The inner tower is enclosed in plan by the lower mill body. Generic
        // rows start at ground level and are all culled by that enclosing
        // mass, leaving only a one-off fallback vent. Author two compact tiers
        // wholly within the exposed upper stage instead.
        outer_height := structure.height * footprint.masses[0].height_scale
        exposed_height := wall_height - outer_height
        for face in faces {
            span := face_span(mass, face)
            if span < ARCHITECTURE_MIN_OPENING_FACE_SPAN do continue
            window_width, window_height := facade_profile_window_size(profile, structure, face)
            // Leave a tiny numerical cushion around the paired .55 m sill and
            // head clearances; an exactly fitted compact vent can otherwise
            // be rejected by the subsequent floating-point bounds check.
            available_vent_height := exposed_height - 1.102
            if available_vent_height < .45 do continue
            window_height = min(window_height, available_vent_height)
            tier_pitch := window_height + .70
            tier_count := clamp(int(math.floor(f64((exposed_height - 1.10 + .70) / tier_pitch))), 1, 2)
            for tier in 0 ..< tier_count {
                opening_y := outer_height + .55 + window_height * .5 + f32(tier) * tier_pitch
                if opening_y + window_height * .5 > wall_height - .55 do continue
                if architecture_opening_occluded_by_mass(
                    footprint,
                    mass_index,
                    face,
                    0,
                    opening_y,
                    window_width,
                    window_height,
                    structure.height,
                ) {
                    continue
                }
                _ = opening_layout_add(
                    layout,
                    {
                        face = face,
                        kind = .Vent,
                        horizontal = 0,
                        y = opening_y,
                        width = window_width,
                        height = window_height,
                        row = facade_floor_count(outer_height) + tier,
                        column = 0,
                    },
                )
            }
        }
    }

    if (!primary_mass && habitable) || profile.service {
        fallback_kind := habitable || workshop_daylight || fishery_work_hall ? Opening_Kind.Window : Opening_Kind.Vent
        has_exposed_opening := false
        for opening in layout.openings[:layout.count] {
            if opening.kind == fallback_kind {
                has_exposed_opening = true
                break
            }
        }
        if !has_exposed_opening {
            // A rear wing can have its only seeded bay removed because that
            // bay lands on the join with the street range. Find one modest
            // exposed opening so the attached volume still reads as occupied
            // or ventilated. Prefer high rows, which can remain visible above
            // a lower adjoining range or the mill's enclosing base mass.
            fallback_faces := [4]Face{.Front, .Left, .Right, .Rear}
            added := false
            for face in fallback_faces {
                span := face_span(mass, face)
                if span < ARCHITECTURE_MIN_OPENING_FACE_SPAN do continue
                profile_face := architecture_paired_profile_face(footprint, mass_index, face)
                window_width, window_height := facade_profile_window_size(profile, structure, profile_face)
                centers := [3]f32{0, -span * .25, span * .25}
                reference_rows := facade_profile_row_count(profile, structure.height, window_height)
                reference_pitch := facade_opening_row_pitch(structure.height, reference_rows, window_height)
                desired_fallback_rows := facade_profile_row_count(profile, wall_height, window_height)
                fallback_rows := facade_opening_row_count_for_pitch(
                    wall_height,
                    window_height,
                    desired_fallback_rows,
                    reference_pitch,
                )
                for reverse_row in 0 ..< fallback_rows {
                    row := fallback_rows - reverse_row - 1
                    opening_y := facade_opening_row_y_for_pitch(row, window_height, reference_pitch)
                    if storehouse_high_vents {
                        opening_y = wall_height - window_height * .5 - 1.10
                    } else if market_basilica_aisle {
                        opening_y = wall_height - window_height * .5 - 1.10
                    }
                    for horizontal, column in centers {
                        if math.abs(horizontal) + window_width * .5 > span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN {
                            continue
                        }
                        if opening_layout_conflicts_with_door(
                            layout,
                            face,
                            horizontal,
                            opening_y,
                            window_width,
                            window_height,
                        ) {
                            continue
                        }
                        if architecture_opening_occluded_by_mass(
                            footprint,
                            mass_index,
                            face,
                            horizontal,
                            opening_y,
                            window_width,
                            window_height,
                            structure.height,
                        ) {
                            continue
                        }
                        _ = opening_layout_add(
                            layout,
                            {
                                face = face,
                                kind = fallback_kind,
                                horizontal = horizontal,
                                y = opening_y,
                                width = window_width,
                                height = window_height,
                                row = row,
                                column = column,
                            },
                        )
                        added = true
                        break
                    }
                    if added do break
                }
                if added do break
            }
        }
    }
    if barn_range {
        has_vent := false
        for opening in layout.openings[:layout.count] {
            if opening.kind == .Vent {
                has_vent = true
                break
            }
        }
        if !has_vent {
            // A compact side aisle may expose only the cart-door wall. When
            // the parent's sill rhythm leaves no lateral bay, use the clear
            // hayloft band above that door instead of sealing the range or
            // squeezing a vent beside the jamb.
            for opening in layout.openings[:layout.count] {
                if opening.kind != .Service_Door do continue
                profile_face := architecture_paired_profile_face(footprint, mass_index, opening.face)
                vent_width, vent_height := facade_profile_window_size(profile, structure, profile_face)
                door_top := opening.y + opening.height * .5
                available_height := wall_height - .55 - door_top - ARCHITECTURE_WINDOW_PIER_MARGIN
                vent_height = min(vent_height, available_height)
                if vent_height < profile.window_height_min - .001 do continue
                vent_y := wall_height - .55 - vent_height * .5
                if architecture_opening_occluded_by_mass(
                    footprint,
                    mass_index,
                    opening.face,
                    opening.horizontal,
                    vent_y,
                    vent_width,
                    vent_height,
                    structure.height,
                ) {
                    continue
                }
                _ = opening_layout_add(
                    layout,
                    {
                        face = opening.face,
                        kind = .Vent,
                        horizontal = opening.horizontal,
                        y = vent_y,
                        width = vent_width,
                        height = vent_height,
                        row = 1,
                        column = 0,
                    },
                )
                break
            }
        }
    }
    if !primary_mass && occupied_secondary_daylight {
        has_lower_window, has_upper_window := false, false
        for opening in layout.openings[:layout.count] {
            if opening.kind != .Window do continue
            if opening.row == 0 {
                has_lower_window = true
            } else {
                has_upper_window = true
            }
        }
        if !has_lower_window {
            _ = architecture_opening_layout_add_habitable_row_fallback(
                layout,
                footprint,
                structure,
                mass_index,
                profile,
                0,
            )
        }
        if facade_floor_count(wall_height) > 1 && !has_upper_window {
            _ = architecture_opening_layout_add_habitable_row_fallback(
                layout,
                footprint,
                structure,
                mass_index,
                profile,
                1,
            )
        }
    }
    if habitable || identity.archetype == .Post_Office {
        // A mass-level fallback can satisfy daylight by placing its lone pane
        // on another elevation, leaving a useful garden, court, or street wall
        // blank when a centered service door or attached range removes the
        // seeded bay. Repair each materially exposed elevation independently;
        // joined seams and intentionally blank gables stay quiet.
        daylight_faces := [4]Face{.Front, .Rear, .Left, .Right}
        for face in daylight_faces {
            if (face == .Left || face == .Right) &&
               profile.blank_sides &&
               !architecture_face_follows_long_axis(mass, face) {
                continue
            }
            span := face_span(mass, face)
            if span < 6 do continue
            exposed_area := architecture_exposed_face_area(footprint, mass_index, face, structure.height)
            if exposed_area < span * wall_height * .20 do continue
            has_face_daylight := false
            for opening in layout.openings[:layout.count] {
                if opening.face == face && (opening.kind == .Window || opening.kind == .Loggia) {
                    has_face_daylight = true
                    break
                }
            }
            if has_face_daylight do continue
            profile_face := architecture_paired_profile_face(footprint, mass_index, face)
            _, window_height := facade_profile_window_size(profile, structure, profile_face)
            desired_rows := facade_profile_row_count(profile, wall_height, window_height)
            for reverse_row in 0 ..< desired_rows {
                row := desired_rows - reverse_row - 1
                if architecture_opening_layout_add_habitable_row_on_face(
                    layout,
                    footprint,
                    structure,
                    mass_index,
                    profile,
                    face,
                    row,
                ) {
                    break
                }
            }
        }
    }
    normalize_ordinary_glazing :=
        !profile.service && (!profile.shop_ground_floor || !primary_mass) && identity.archetype != .Market_Hall
    if normalize_ordinary_glazing && profile.opening_ratio_max > 0 {
        // A single minimum-size pane can exceed a compact wall's ratio ceiling,
        // while a broad compound face can retain a full seeded band after an
        // attachment buries most of its actual wall. Preserve rhythm and aspect
        // ratios, but scale ordinary glazing uniformly to the exposed-area
        // budget at every span. Purpose-defining storefronts and arcades remain
        // exempt because their openings describe program rather than a generic
        // daylight percentage.
        for face in faces {
            authored_primary_front :=
                primary_mass &&
                face == .Front &&
                (identity.archetype == .Palace_Loggia ||
                        identity.archetype == .Market_Hall ||
                        identity.archetype == .Monastery)
            if authored_primary_front do continue
            glazing_area := f32(0)
            for opening in layout.openings[:layout.count] {
                if opening.face == face && opening.kind == .Window {
                    glazing_area += opening.width * opening.height
                }
            }
            exposed_wall_area := architecture_exposed_face_area(footprint, mass_index, face, structure.height)
            span := face_span(mass, face)
            full_wall_area := span * wall_height
            minimum_target_area := profile.opening_ratio_min * exposed_wall_area
            if span >= 28 &&
               exposed_wall_area >= full_wall_area * .75 &&
               glazing_area > .001 &&
               glazing_area < minimum_target_area - .001 {
                // A broad stepped join can bury every seeded center even when
                // most of the wall remains exterior. Fill safe edge/center
                // candidates row by row before resizing anything; repeated
                // calls advance naturally because existing panes reject the
                // positions already claimed in earlier rounds.
                _, fallback_window_height := facade_profile_window_size(profile, structure, face)
                fallback_storeys := facade_floor_count(wall_height)
                if profile.rows_max > 0 do fallback_storeys = min(fallback_storeys, profile.rows_max)
                if fallback_storeys > 1 {
                    fitted_fallback_height :=
                        (wall_height - 2 * 1.45 - f32(fallback_storeys - 1) * .35) / f32(fallback_storeys)
                    fallback_window_height = min(fallback_window_height, max(f32(.75), fitted_fallback_height - .01))
                }
                fallback_rows := facade_profile_row_count(profile, wall_height, fallback_window_height)
                for _ in 0 ..< 16 {
                    added_round := false
                    for row in 0 ..< fallback_rows {
                        if glazing_area >= minimum_target_area - .001 do break
                        previous_count := layout.count
                        if architecture_opening_layout_add_habitable_row_on_face(
                            layout,
                            footprint,
                            structure,
                            mass_index,
                            profile,
                            face,
                            row,
                        ) {
                            added := layout.openings[previous_count]
                            glazing_area += added.width * added.height
                            added_round = true
                        }
                    }
                    if glazing_area >= minimum_target_area - .001 || !added_round do break
                }
                // Join culling can remove part of a broad row after bay count
                // has met its nominal ratio, leaving a mostly exposed wall a
                // few percent below its daylight floor. Grow panes vertically
                // only: horizontal door, corner, and neighbor clearances stay
                // untouched. Cap growth at wall heads/sills and adjacent rows.
                height_scale := minimum_target_area / glazing_area
                maximum_height_scale := height_scale
                for opening, opening_index in layout.openings[:layout.count] {
                    if opening.face != face || opening.kind != .Window do continue
                    wall_fit := 2 * min(opening.y, wall_height - opening.y) / max(opening.height, f32(.001))
                    maximum_height_scale = min(maximum_height_scale, wall_fit)
                    for candidate, candidate_index in layout.openings[:layout.count] {
                        if candidate_index <= opening_index || candidate.face != face || candidate.kind != .Window {
                            continue
                        }
                        horizontal_overlap :=
                            math.abs(opening.horizontal - candidate.horizontal) <
                            (opening.width + candidate.width) * .5 - .001
                        if !horizontal_overlap do continue
                        row_fit :=
                            2 * math.abs(opening.y - candidate.y) / max(opening.height + candidate.height, f32(.001))
                        maximum_height_scale = min(maximum_height_scale, row_fit)
                    }
                }
                safe_maximum_height_scale := max(f32(1), maximum_height_scale)
                applied_height_scale := min(height_scale, safe_maximum_height_scale)
                if applied_height_scale > 1 {
                    for opening, opening_index in layout.openings[:layout.count] {
                        if opening.face != face || opening.kind != .Window do continue
                        layout.openings[opening_index].height *= applied_height_scale
                    }
                    glazing_area *= applied_height_scale
                }
            }
            target_area := profile.opening_ratio_max * exposed_wall_area
            if glazing_area <= target_area + .001 || glazing_area <= .001 do continue
            scale := f32(math.sqrt(f64(target_area / glazing_area)))
            for opening, opening_index in layout.openings[:layout.count] {
                if opening.face != face || opening.kind != .Window do continue
                layout.openings[opening_index].width *= scale
                layout.openings[opening_index].height *= scale
            }
        }
    }
}
