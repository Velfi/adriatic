package architecture

import "core:math"

architecture_opening_layout_add_faces :: proc(layout: ^Opening_Layout, ctx: Architecture_Opening_Face_Context) {
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
    for face in faces {
        span := face_span(mass, face)
        if span < ARCHITECTURE_MIN_OPENING_FACE_SPAN do continue
        // The fortress's public entrance is the open slot between its paired
        // towers. Treating the arbitrarily selected frontage tower as an
        // ordinary primary mass punches a domestic-scale door beside the
        // gate and weakens the defensive silhouette.
        primary_face :=
            primary_mass && face == .Front && (identity.archetype != .Fortress_Gate || footprint.count == 1)
        guard_court_entry :=
            identity.archetype == .Fortress_Gate && footprint.count == 3 && mass_index == 2 && face == .Front
        utility_yard_entry :=
            (farmstead_work_range ||
                shop_stock_range ||
                harbor_service_range ||
                storehouse_loading_range ||
                fishery_smokehouse_range ||
                market_loading_range ||
                market_basilica_aisle) &&
            face == .Rear
        barn_aisle_entry :=
            identity.archetype == .Barn_Granary &&
            footprint.count == 2 &&
            mass_index == 1 &&
            face == (mass.local_x < 0 ? Face.Left : Face.Right)
        productive_court_hall_entry :=
            (identity.archetype == .Workshop || identity.archetype == .Storehouse || identity.archetype == .Fishery) &&
            footprint.count == 3 &&
            mass_index == 0 &&
            structure.seed % 6 == 4 &&
            face == .Front
        church_chancel_entry :=
            identity.archetype == .Church && footprint.count == 3 && mass_index == 2 && face == .Rear
        monastery_service_entry :=
            identity.archetype == .Monastery && footprint.count == 3 && mass_index == 0 && face == .Rear
        palace_wing_entry :=
            identity.archetype == .Palace_Loggia &&
            footprint.count == 3 &&
            (mass_index == 1 || mass_index == 2) &&
            (face == .Rear || face == (mass_index == 1 ? Face.Right : Face.Left))
        monastery_cell_court_entry :=
            identity.archetype == .Monastery &&
            footprint.count == 3 &&
            (mass_index == 1 || mass_index == 2) &&
            face == (mass_index == 1 ? Face.Right : Face.Left)
        harbor_yard_entry :=
            identity.archetype == .Harbor_Office &&
            footprint.count == 3 &&
            mass_index > 0 &&
            face == (mass.local_x < 0 ? Face.Right : Face.Left)
        domestic_court_wing_entry :=
            (identity.archetype == .Dwelling || identity.archetype == .Farmstead) &&
            footprint.count == 3 &&
            structure.seed % 8 == 3 &&
            (mass_index == 1 || mass_index == 2) &&
            (face == .Rear || face == (mass_index == 1 ? Face.Right : Face.Left))
        domestic_return_entry :=
            (identity.archetype == .Dwelling ||
                identity.archetype == .Farmstead ||
                identity.archetype == .Townhouse ||
                identity.archetype == .Shop_House) &&
            footprint.count == 2 &&
            mass_index == 1 &&
            face == .Rear
        civic_return_entry :=
            (identity.archetype == .Palace_Loggia ||
                identity.archetype == .Market_Hall ||
                identity.archetype == .Harbor_Office ||
                identity.archetype == .Monastery ||
                identity.archetype == .Post_Office ||
                identity.archetype == .Clinic) &&
            footprint.count >= 2 &&
            mass_index == 1 &&
            face == .Rear &&
            (footprint.count == 2 || identity.archetype == .Palace_Loggia || identity.archetype == .Harbor_Office)
        clinic_ward_entry :=
            identity.archetype == .Clinic &&
            mass_index > 0 &&
            (face == .Rear || (footprint.count == 3 && face == (mass_index == 1 ? Face.Right : Face.Left)))
        post_work_entry := identity.archetype == .Post_Office && mass_index > 0 && face == .Rear
        post_parcel_annex_entry :=
            identity.archetype == .Post_Office && footprint.count == 3 && mass_index == 2 && face == .Rear
        mixed_use_private_entry :=
            identity.archetype == .Mixed_Use_Dwelling &&
            ((footprint.count == 2 && mass_index == 1 && face == .Rear) ||
                    (footprint.count == 3 && mass_index == 1 && face == .Right) ||
                    (footprint.count == 3 && mass_index == 2 && face == .Left))
        mixed_use_apartment_entry :=
            identity.archetype == .Mixed_Use_Dwelling &&
            primary_mass &&
            wall_height >= 7.2 &&
            face == mixed_use_apartment_face
        secondary_service_entry :=
            guard_court_entry ||
            utility_yard_entry ||
            barn_aisle_entry ||
            productive_court_hall_entry ||
            church_chancel_entry ||
            monastery_service_entry ||
            palace_wing_entry ||
            monastery_cell_court_entry ||
            harbor_yard_entry ||
            domestic_court_wing_entry ||
            domestic_return_entry ||
            civic_return_entry ||
            clinic_ward_entry ||
            post_work_entry ||
            mixed_use_private_entry ||
            mixed_use_apartment_entry
        profile_face := architecture_paired_profile_face(footprint, mass_index, face)
        compact_storefront :=
            primary_face &&
            profile.shop_ground_floor &&
            ((identity.archetype == .Mixed_Use_Dwelling && span < 14) ||
                    (identity.archetype == .Shop_House && span < 10))
        compact_market_arcade := primary_face && identity.archetype == .Market_Hall && span < 15
        compact_palace_loggia := primary_face && identity.archetype == .Palace_Loggia && span < 8
        compact_ground_frontage := compact_storefront || compact_market_arcade || compact_palace_loggia
        compact_frontage_door_side := (structure.seed & 1) == 0 ? f32(-1) : f32(1)
        door_width := f32(0)
        if primary_face || secondary_service_entry {
            door_width = clamp(span * .13, f32(1.8), f32(2.8))
            door_height := clamp(wall_height * .075, f32(3.0), f32(4.0))
            if primary_face && identity.archetype == .Barn_Granary {
                // A compact double plank leaf admits a handcart or small farm
                // cart without turning the elevation into a hay-hall portal.
                door_width = clamp(span * .20, f32(2.6), f32(3.8))
                door_height = clamp(wall_height * .18, f32(3.2), f32(4.2))
            } else if primary_face && identity.archetype == .Storehouse {
                door_width = clamp(span * .20, f32(3.4), f32(5.0))
                door_height = clamp(wall_height * .19, f32(4.0), f32(5.5))
            } else if primary_face && identity.archetype == .Workshop {
                // The work-hall entrance must pass benches, stock, and small
                // machinery. A domestic service leaf contradicts the broad
                // high-light workshop elevation it organizes.
                door_width = clamp(span * .18, f32(3.2), f32(4.8))
                door_height = clamp(wall_height * .18, f32(3.8), f32(5.0))
            } else if primary_face && identity.archetype == .Fishery {
                // Fishery halls move crates and handcarts through a washable
                // working frontage, but need not match a warehouse portal.
                door_width = clamp(span * .17, f32(3.0), f32(4.4))
                door_height = clamp(wall_height * .17, f32(3.6), f32(4.8))
            } else if storehouse_loading_range && face == .Rear {
                door_width = clamp(span * .25, f32(3.2), f32(4.8))
                door_height = clamp(wall_height * .28, f32(3.8), f32(5.0))
            } else if (market_loading_range || market_basilica_aisle) && face == .Rear {
                // The rear stem of the T-plan is the market's produce and
                // stall-loading hall. Preserve the centered public-to-service
                // circulation axis, but size its yard portal for handcarts
                // and loaded barrows instead of an ordinary civic side door.
                door_width = clamp(span * .24, f32(3.4), f32(5.0))
                door_height = clamp(wall_height * .25, f32(3.8), f32(5.0))
            } else if barn_aisle_entry {
                door_width = clamp(span * .20, f32(2.2), f32(3.2))
                door_height = clamp(wall_height * .24, f32(3.0), f32(3.8))
            } else if post_parcel_annex_entry {
                // The side annex is the cart-facing parcel dock, while the
                // centered sorting range retains a staff-scale yard door.
                // Giving both ranges the same narrow leaf hid their distinct
                // circulation roles and made bulk mail arrive through a
                // pedestrian opening.
                door_width = clamp(span * .30, f32(3.0), f32(4.2))
                door_height = clamp(wall_height * .30, f32(3.4), f32(4.6))
            } else if mixed_use_private_entry {
                // Match the complete jamb-and-lintel envelope drawn by the
                // bespoke private-entry renderer, rather than only its leaf.
                door_width = 1.66
                door_height = 3.02
            } else if mixed_use_apartment_entry {
                door_width = 1.65
                door_height = 3.05
            }
            broad_public_entrance :=
                primary_face &&
                span >= 28 &&
                wall_height >= 14.4 &&
                (identity.archetype == .Post_Office ||
                        identity.archetype == .Clinic ||
                        identity.archetype == .Palace_Loggia ||
                        identity.archetype == .Market_Hall ||
                        identity.archetype == .Harbor_Office ||
                        identity.archetype == .Monastery ||
                        identity.archetype == .Church)
            broad_urban_entrance :=
                primary_face &&
                span >= 28 &&
                wall_height >= 14.4 &&
                (identity.archetype == .Townhouse ||
                        identity.archetype == .Shop_House ||
                        identity.archetype == .Mixed_Use_Dwelling)
            if broad_public_entrance {
                // A civic frontage needs a legible pair of public leaves, but
                // it must remain distinct from cart-scale productive portals.
                door_width = clamp(span * .075, f32(3.2), f32(4.0))
                door_height = clamp(wall_height * .10, f32(4.2), f32(4.8))
            } else if broad_urban_entrance {
                // Metropolitan residential and shop bars use a restrained
                // double-leaf entry instead of stretching a domestic leaf to
                // the same 2.8 m cap on every large elevation.
                door_width = clamp(span * .060, f32(3.0), f32(3.4))
                door_height = clamp(wall_height * .09, f32(4.0), f32(4.5))
            }
            // Retain the shared corner and head clearance on compact authored
            // structures even when their program asks for a cart-scale leaf.
            door_width = min(door_width, max(f32(.8), span - ARCHITECTURE_OPENING_CORNER_MARGIN * 2))
            door_height = min(door_height, max(f32(.8), wall_height - .40))
            door_y := .20 + door_height * .5
            if mixed_use_private_entry do door_y = door_height * .5
            door_horizontal := f32(0)
            if compact_ground_frontage {
                // Pull the entrance to one jamb so the shortened frontage can
                // spend its remaining width on useful display or arcade bay.
                door_horizontal =
                    compact_frontage_door_side * (span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - door_width * .5)
            } else if mixed_use_apartment_entry {
                door_y = 1.62
                desired_horizontal := face == .Left ? mass.depth * .20 : -mass.depth * .20
                maximum_horizontal := max(f32(0), span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - door_width * .5)
                // The apartment entrance favors the streetward end of each
                // side wall, but shallow mixed-use lots cannot sustain the
                // full proportional offset. Clamp the bespoke doorway to the
                // same jamb-to-corner clearance as generated windows.
                door_horizontal = clamp(desired_horizontal, -maximum_horizontal, maximum_horizontal)
            }
            door_occluded := architecture_opening_occluded_by_mass(
                footprint,
                mass_index,
                face,
                door_horizontal,
                door_y,
                door_width,
                door_height,
                structure.height,
            )
            if door_occluded {
                // Compact L and working-court plans can project an attachment
                // across the centered jamb even though another broad part of
                // the same approach wall remains exterior. Keep the authored
                // centerline when it is usable; otherwise search symmetric
                // quarter/edge bays for the nearest exposed entrance.
                maximum_door_center := max(f32(0), span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - door_width * .5)
                fallback_centers := [4]f32 {
                    -min(span * .25, maximum_door_center),
                    min(span * .25, maximum_door_center),
                    -maximum_door_center,
                    maximum_door_center,
                }
                for fallback_center in fallback_centers {
                    if architecture_opening_occluded_by_mass(
                        footprint,
                        mass_index,
                        face,
                        fallback_center,
                        door_y,
                        door_width,
                        door_height,
                        structure.height,
                    ) {
                        continue
                    }
                    door_horizontal = fallback_center
                    door_occluded = false
                    break
                }
            }
            if !door_occluded {
                _ = opening_layout_add(
                    layout,
                    {
                        face = face,
                        kind = primary_face && habitable ? Opening_Kind.Door : Opening_Kind.Service_Door,
                        horizontal = door_horizontal,
                        y = door_y,
                        width = door_width,
                        height = door_height,
                        primary = primary_face,
                    },
                )
            }
        }

        bay_profile := profile
        domestic_u_court_face :=
            (identity.archetype == .Dwelling || identity.archetype == .Farmstead) &&
            footprint.count == 3 &&
            structure.seed % 8 == 3 &&
            (mass_index == 1 || mass_index == 2) &&
            face == (mass_index == 1 ? Face.Right : Face.Left)
        if domestic_u_court_face {
            // Rural blank-side policy belongs on exposed party/gable walls,
            // not on the inhabited faces enclosing a private rear court.
            // Give each wing a modest inward-looking rhythm while its court
            // door continues to own the ground circulation bay.
            bay_profile.blank_sides = false
            bay_profile.side_bays_min = 1
            bay_profile.side_bays_max = max(bay_profile.side_bays_max, 2)
        }
        if identity.archetype == .Monastery && footprint.count == 3 && mass_index == 0 && primary_face {
            // The paired cell ranges bury predictable strips of the communal
            // range's court-facing wall. Seed against a small pre-cull reserve
            // so the remaining exposed façade still meets the public 8% floor.
            bay_profile.opening_ratio_min = min(profile.opening_ratio_max, profile.opening_ratio_min + .01)
        }
        columns := facade_profile_bay_count(bay_profile, structure, profile_face, primary_face, span, wall_height)
        if habitable && architecture_face_follows_long_axis(mass, face) && columns <= 0 {
            // Blank-side profiles describe subordinate gable ends, not the
            // principal elevation of a deep bar. Always retain at least one
            // daylight bay on walls that follow the footprint's longest axis.
            columns = 1
        }
        if compact_ground_frontage {
            // The shifted entrance and fitted display pane are a one-bay
            // compact grammar. Seeded multi-bay counts would retain the broad
            // shop or market sizing path and cull every bay against the door.
            columns = 1
        }
        if market_basilica_nave && primary_face {
            // The nave is deliberately narrower than a T-plan's street bar.
            // Cap its arcade at four useful trading bays instead of squeezing
            // the generic six-bay maximum into sub-two-metre openings.
            columns = min(columns, 4)
        }
        if columns <= 0 do continue
        window_width, window_height := facade_profile_window_size(profile, structure, profile_face)
        storey_rows := facade_floor_count(wall_height)
        if profile.rows_max > 0 do storey_rows = min(storey_rows, profile.rows_max)
        if storey_rows > 1 {
            // At the exact two-storey threshold, a tall randomized pane can
            // consume the vertical wall band needed by the second level.
            // Fit height—not width or bay count—to preserve both daylight
            // rows and the profile's horizontal character.
            fitted_window_height := (wall_height - 2 * 1.45 - f32(storey_rows - 1) * .35) / f32(storey_rows)
            // Leave a centimetre of numerical tolerance so the subsequent
            // row-count floor does not reject an exactly fitted second pane.
            window_height = min(window_height, max(f32(.75), fitted_window_height - .01))
        }
        // Residential compounds share parent-storey datums. Barn ranges have
        // independent loft floors under unequal roof heights, so distribute
        // their two ventilation levels within each range's actual wall.
        independent_range_pitch := barn_range || farmstead_work_range || shop_stock_range || post_sorting_range
        reference_height := independent_range_pitch ? wall_height : structure.height
        reference_rows := facade_profile_row_count(profile, reference_height, window_height)
        reference_pitch := facade_opening_row_pitch(reference_height, reference_rows, window_height)
        desired_face_rows := facade_profile_row_count(profile, wall_height, window_height)
        vertical_service_openings := fortress_tower || bell_tower || barn_range
        face_rows :=
            profile.service && !vertical_service_openings ? 1 : facade_opening_row_count_for_pitch(wall_height, window_height, desired_face_rows, reference_pitch)
        if !profile.service && face_rows < desired_face_rows && desired_face_rows > 1 {
            // A compact secondary range can cross the two-storey threshold
            // while remaining too short for its parent's upper sill. Retain
            // shared datums where possible, then fall back to the range's own
            // fitted pitch so an occupied level never becomes windowless.
            reference_pitch = facade_opening_row_pitch(wall_height, desired_face_rows, window_height)
            face_rows = desired_face_rows
        }
        for row in 0 ..< face_rows {
            if bell_tower && row < face_rows - 1 {
                // Follow the internal stair with one slit per lower level,
                // cycling across rear and side walls. Reserve the complete
                // four-face rhythm for the open bell chamber at the top, and
                // keep the entrance facade quiet below it.
                stair_face := 1 + int((structure.seed + u32(row)) % 3)
                if int(face) != stair_face do continue
            }
            opening_y := facade_opening_row_y_for_pitch(row, window_height, reference_pitch)
            for column in 0 ..< columns {
                horizontal := facade_bay_center(span, window_width, columns, column)
                central_bay := columns % 2 == 1 && column == columns / 2
                if primary_face && row == 0 && central_bay && !compact_ground_frontage {
                    continue
                }
                if math.abs(horizontal) + window_width * .5 > span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN {
                    continue
                }
                kind := Opening_Kind.Window
                opening_height := window_height
                opening_width := window_width
                principal_floor_archetype :=
                    identity.archetype == .Dwelling ||
                    identity.archetype == .Farmstead ||
                    identity.archetype == .Townhouse ||
                    identity.archetype == .Shop_House ||
                    identity.archetype == .Mixed_Use_Dwelling ||
                    identity.archetype == .Post_Office ||
                    identity.archetype == .Clinic
                if principal_floor_archetype &&
                   primary_face &&
                   span >= 28 &&
                   columns >= 7 &&
                   face_rows >= 3 &&
                   row == 1 {
                    // Give the first upper occupied floor a restrained
                    // horizontal emphasis. Preserve pane area exactly so the
                    // hierarchy changes architectural character without
                    // inflating the glazing ratio or weakening daylight on
                    // any other level.
                    principal_scale := f32(1.12)
                    opening_width *= principal_scale
                    opening_height /= principal_scale
                }
                if harbor_dispatch_range && face_rows > 1 && row == face_rows - 1 {
                    // The upper dispatch/watch room scans the quay through a
                    // broader horizontal band. Fit enlargement to the actual
                    // bay pitch and corner clearance so compact wings cannot
                    // overlap neighboring panes.
                    desired_width := window_width * 1.28
                    if columns > 1 {
                        next_center := facade_bay_center(span, window_width, columns, min(column + 1, columns - 1))
                        previous_center := facade_bay_center(span, window_width, columns, max(column - 1, 0))
                        neighbor_pitch :=
                            column < columns - 1 ? math.abs(next_center - horizontal) : math.abs(horizontal - previous_center)
                        desired_width = min(desired_width, max(window_width, neighbor_pitch - .55))
                    }
                    corner_fit := (span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - math.abs(horizontal)) * 2
                    opening_width = min(desired_width, max(window_width, corner_fit))
                    opening_height = min(window_height * 1.10, f32(2.25))
                    opening_y = min(opening_y, wall_height - opening_height * .5 - .75)
                }
                if workshop_daylight || fishery_work_hall || market_basilica_aisle {
                    kind = .Window
                    opening_y = wall_height - opening_height * .5 - 1.10
                } else if storehouse_high_vents {
                    kind = .Vent
                    opening_y = wall_height - opening_height * .5 - 1.10
                } else if profile.service {
                    kind = .Vent
                    if !vertical_service_openings {
                        opening_y = max(opening_height * .5 + 1.15, f32(1.5))
                    }
                } else if profile.shop_ground_floor && primary_face && row == 0 {
                    // Shop glazing should begin near the pavement and approach
                    // the door head. Treating it like a slightly enlarged
                    // domestic window leaves the ground floor visually closed.
                    if compact_storefront && columns == 1 {
                        // A narrow shop cannot carry its ordinary pair of
                        // display panes. Fit one useful pane into the band
                        // opposite the side-shifted entrance while preserving
                        // both the corner and door clearances.
                        available_width :=
                            span -
                            ARCHITECTURE_OPENING_CORNER_MARGIN * 2 -
                            door_width -
                            ARCHITECTURE_DOOR_WINDOW_MARGIN
                        opening_width = clamp(available_width, f32(.70), f32(5.20))
                    } else if identity.archetype == .Mixed_Use_Dwelling {
                        if columns <= 2 {
                            opening_width = clamp(span * .27, f32(4.2), f32(7.2))
                        } else {
                            // Very broad mixed-use bars grow beyond the
                            // ordinary two display bays. Fit those panes to the
                            // generated rhythm instead of repeating the 7.2 m
                            // two-bay width until neighboring panes overlap.
                            opening_width = clamp(
                                (span - ARCHITECTURE_OPENING_CORNER_MARGIN * 2) / f32(columns) * .60,
                                f32(2.35),
                                f32(5.20),
                            )
                        }
                    } else {
                        opening_width = clamp(span / f32(columns + 1) * .62, f32(2.35), f32(3.60))
                    }
                    opening_height = min(window_height * 1.62, f32(3.40))
                    opening_y = .36 + opening_height * .5
                } else if identity.archetype == .Palace_Loggia && primary_face && row == 0 {
                    // The palace name must appear in its plan/elevation: tall
                    // open ground bays flank the ceremonial door while upper
                    // residential/state rooms retain glazed windows.
                    kind = .Loggia
                    opening_width = clamp(span / f32(columns + 1) * .58, f32(2.10), f32(3.20))
                    opening_height = min(clamp(wall_height * .16, f32(3.80), f32(4.80)), wall_height - .50)
                    opening_y = .25 + opening_height * .5
                } else if monastery_cloister_range && primary_face && row == 0 {
                    // The communal range faces the open cloister court between
                    // its cell wings. Make that ground band a shaded arcade,
                    // while upper cells and library rooms retain glazing.
                    kind = .Loggia
                    opening_width = clamp(span / f32(columns + 1) * .50, f32(1.55), f32(2.35))
                    opening_height = min(clamp(wall_height * .145, f32(3.20), f32(4.20)), wall_height - .50)
                    opening_y = .25 + opening_height * .5
                } else if identity.archetype == .Market_Hall && primary_face && row == 0 {
                    // Public trading spills through a permeable ground arcade;
                    // the second tier remains glazed clerestory light over the
                    // market floor.
                    kind = .Loggia
                    opening_width = clamp(span / f32(columns + 1) * .56, f32(2.00), f32(3.50))
                    opening_height = min(clamp(wall_height * .15, f32(3.40), f32(4.60)), wall_height - .50)
                    opening_y = .20 + opening_height * .5
                } else if primary_face && row == 0 {
                    opening_width *= .90
                    opening_height *= .85
                    opening_y = facade_opening_row_y(wall_height, row, opening_height)
                }
                if columns > 1 {
                    // Program-specific storefront and arcade panes can grow
                    // wider than the ordinary window module used to place
                    // their bay centers. Fit every enlarged opening to its
                    // local interval so adjacent panes retain a real masonry
                    // pier on irregular broad-façade rhythms.
                    neighbor_pitch := f32(0)
                    if column > 0 {
                        previous_center := facade_bay_center(span, window_width, columns, column - 1)
                        neighbor_pitch = math.abs(horizontal - previous_center)
                    }
                    if column < columns - 1 {
                        next_center := facade_bay_center(span, window_width, columns, column + 1)
                        next_pitch := math.abs(next_center - horizontal)
                        neighbor_pitch = neighbor_pitch <= 0 ? next_pitch : min(neighbor_pitch, next_pitch)
                    }
                    opening_width = min(opening_width, max(f32(.70), neighbor_pitch - ARCHITECTURE_WINDOW_PIER_MARGIN))
                }
                if kind == .Loggia && primary_face && row == 0 {
                    // Fit every arcade grammar—not only markets—to the actual
                    // half-façade interval between the entrance clearance and
                    // corner margin. Compact palaces otherwise overlap their
                    // minimum-width loggia bays before placement begins.
                    side_columns := max(columns / 2, 1)
                    usable_half_band :=
                        span * .5 -
                        ARCHITECTURE_OPENING_CORNER_MARGIN -
                        door_width * .5 -
                        ARCHITECTURE_DOOR_WINDOW_MARGIN
                    fit_width :=
                        (usable_half_band - f32(side_columns - 1) * ARCHITECTURE_WINDOW_PIER_MARGIN) /
                        f32(side_columns)
                    opening_width = min(opening_width, max(f32(.90), fit_width))
                }
                if primary_face && row == 0 {
                    // Lay each half of the ground-floor rhythm into the band
                    // between the corner margin and centered entrance. Merely
                    // nudging an inner bay away from the door can push it into
                    // its unchanged outer neighbor on four- and five-bay civic
                    // façades.
                    if compact_ground_frontage && columns == 1 {
                        // Mirror the lone display or arcade bay across from
                        // the side entrance, retaining the same corner datum
                        // as the full multi-bay frontage.
                        horizontal =
                            -compact_frontage_door_side *
                            (span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - opening_width * .5)
                    }
                    // Decide redistribution for the whole façade from its
                    // innermost surviving bay. Moving only the bay that
                    // directly conflicts with the door compresses it against
                    // an unchanged neighbor and can leave a paper-thin pier.
                    inner_column := max(columns / 2 - 1, 0)
                    inner_horizontal := facade_bay_center(span, window_width, columns, inner_column)
                    facade_needs_door_redistribution :=
                        !compact_ground_frontage &&
                        columns > 1 &&
                        opening_layout_conflicts_with_door(
                            layout,
                            face,
                            inner_horizontal,
                            opening_y,
                            opening_width,
                            opening_height,
                        )
                    if compact_ground_frontage || facade_needs_door_redistribution {
                        side_columns := max(columns / 2, 1)
                        if facade_needs_door_redistribution {
                            usable_half_band :=
                                span * .5 -
                                ARCHITECTURE_OPENING_CORNER_MARGIN -
                                door_width * .5 -
                                ARCHITECTURE_DOOR_WINDOW_MARGIN
                            fit_width :=
                                (usable_half_band - f32(side_columns - 1) * ARCHITECTURE_WINDOW_PIER_MARGIN) /
                                f32(side_columns)
                            opening_width = min(opening_width, max(f32(.70), fit_width))
                        }
                        inner_center := door_width * .5 + opening_width * .5 + ARCHITECTURE_DOOR_WINDOW_MARGIN
                        outer_center := span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - opening_width * .5
                        right_start := (columns + 1) / 2
                        if columns > 1 && column < side_columns {
                            t := side_columns <= 1 ? f32(1) : f32(column) / f32(side_columns - 1)
                            horizontal = -(outer_center + (inner_center - outer_center) * t)
                        } else if columns > 1 && column >= right_start {
                            side_column := column - right_start
                            t := side_columns <= 1 ? f32(0) : f32(side_column) / f32(side_columns - 1)
                            horizontal = inner_center + (outer_center - inner_center) * t
                        }
                    }
                    if math.abs(horizontal) + opening_width * .5 > span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN {
                        continue
                    }
                }
                if opening_layout_conflicts_with_door(
                    layout,
                    face,
                    horizontal,
                    opening_y,
                    opening_width,
                    opening_height,
                ) {
                    continue
                }
                if architecture_opening_occluded_by_mass(
                    footprint,
                    mass_index,
                    face,
                    horizontal,
                    opening_y,
                    opening_width,
                    opening_height,
                    structure.height,
                ) {
                    continue
                }
                if opening_layout_conflicts_with_opening(
                    layout,
                    face,
                    horizontal,
                    opening_y,
                    opening_width,
                    opening_height,
                ) {
                    continue
                }
                _ = opening_layout_add(
                    layout,
                    {
                        face = face,
                        kind = kind,
                        horizontal = horizontal,
                        y = opening_y,
                        width = opening_width,
                        height = opening_height,
                        row = row,
                        column = column,
                        primary = primary_face,
                    },
                )
            }
        }
    }
}
