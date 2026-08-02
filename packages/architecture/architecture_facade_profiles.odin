package architecture

import buildings "../buildings"
import terrain "../terrain"
import "core:math"

facade_profile :: proc(archetype: buildings.Archetype) -> Facade_Profile {
    switch archetype {
    case .Dwelling, .Legacy:
        return {
            front_bays_min = 1,
            front_bays_max = 2,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 1,
            side_bays_max = 2,
            window_width_min = 1.05,
            window_width_max = 1.35,
            window_height_min = 1.55,
            window_height_max = 1.90,
            opening_ratio_min = .08,
            opening_ratio_max = .14,
        }
    case .Farmstead:
        return {
            front_bays_min = 1,
            front_bays_max = 2,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 0,
            side_bays_max = 1,
            window_width_min = 1.05,
            window_width_max = 1.35,
            window_height_min = 1.55,
            window_height_max = 1.90,
            opening_ratio_min = .08,
            opening_ratio_max = .14,
            blank_sides = true,
        }
    case .Townhouse:
        return {
            front_bays_min = 2,
            front_bays_max = 3,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 2,
            side_bays_max = 3,
            window_width_min = 1.15,
            window_width_max = 1.50,
            window_height_min = 1.70,
            window_height_max = 2.20,
            opening_ratio_min = .12,
            opening_ratio_max = .20,
        }
    case .Shop_House, .Post_Office, .Clinic:
        return {
            front_bays_min = 2,
            front_bays_max = 3,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 0,
            side_bays_max = 2,
            window_width_min = 1.15,
            window_width_max = 1.50,
            window_height_min = 1.70,
            window_height_max = 2.20,
            opening_ratio_min = .12,
            opening_ratio_max = .20,
            blank_sides = true,
            shop_ground_floor = archetype == .Shop_House,
        }
    case .Mixed_Use_Dwelling:
        return {
            // Two broad display bays flank the glazed shop entrance. Apartment
            // access is handled on the side walls, not by consuming frontage.
            front_bays_min    = 2,
            front_bays_max    = 2,
            rear_bays_min     = 1,
            rear_bays_max     = 2,
            side_bays_min     = 1,
            side_bays_max     = 2,
            window_width_min  = 1.35,
            window_width_max  = 1.70,
            window_height_min = 1.85,
            window_height_max = 2.25,
            opening_ratio_min = .15,
            opening_ratio_max = .22,
            blank_sides       = true,
            shop_ground_floor = true,
        }
    case .Workshop, .Storehouse, .Fishery, .Barn_Granary, .Mill:
        return {
            front_bays_min = 0,
            front_bays_max = 2,
            rear_bays_min = 0,
            rear_bays_max = 1,
            side_bays_min = 0,
            side_bays_max = 1,
            window_width_min = .80,
            window_width_max = 1.35,
            window_height_min = .65,
            window_height_max = 1.20,
            opening_ratio_min = 0,
            opening_ratio_max = .08,
            blank_sides = true,
            service = true,
        }
    case .Church:
        return {
            front_bays_min = 2,
            front_bays_max = 3,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 1,
            side_bays_max = 3,
            window_width_min = 1.00,
            window_width_max = 1.35,
            window_height_min = 2.20,
            window_height_max = 3.00,
            opening_ratio_min = .035,
            opening_ratio_max = .08,
            rows_max = 2,
        }
    case .Monastery:
        return {
            front_bays_min = 2,
            front_bays_max = 4,
            rear_bays_min = 1,
            rear_bays_max = 2,
            side_bays_min = 1,
            side_bays_max = 2,
            window_width_min = .95,
            window_width_max = 1.30,
            window_height_min = 1.70,
            window_height_max = 2.20,
            opening_ratio_min = .08,
            opening_ratio_max = .15,
        }
    case .Market_Hall:
        return {
            // Market halls are broad single-volume rooms. A dense horizontal
            // clerestory rhythm belongs here, but generic floor-count stacking
            // makes the elevation read as a palace or apartment block.
            front_bays_min    = 4,
            front_bays_max    = 6,
            rear_bays_min     = 2,
            rear_bays_max     = 4,
            side_bays_min     = 2,
            side_bays_max     = 4,
            window_width_min  = 1.40,
            window_width_max  = 1.90,
            window_height_min = 2.00,
            window_height_max = 2.60,
            opening_ratio_min = .04,
            opening_ratio_max = .11,
            rows_max          = 2,
        }
    case .Harbor_Office:
        return {
            front_bays_min = 3,
            front_bays_max = 5,
            rear_bays_min = 2,
            rear_bays_max = 3,
            side_bays_min = 1,
            side_bays_max = 3,
            window_width_min = 1.05,
            window_width_max = 1.45,
            window_height_min = 1.55,
            window_height_max = 2.05,
            opening_ratio_min = .045,
            opening_ratio_max = .10,
            rows_max = 3,
        }
    case .Palace_Loggia:
        return {
            front_bays_min = 3,
            front_bays_max = 5,
            rear_bays_min = 1,
            rear_bays_max = 3,
            side_bays_min = 1,
            side_bays_max = 3,
            window_width_min = 1.20,
            window_width_max = 1.70,
            window_height_min = 1.80,
            window_height_max = 2.35,
            opening_ratio_min = .15,
            opening_ratio_max = .24,
        }
    case .Campanile, .Fortress_Gate, .Cycladic_Bell, .Lighthouse:
        return {
            front_bays_min = 0,
            front_bays_max = 1,
            rear_bays_min = 0,
            rear_bays_max = 1,
            side_bays_min = 0,
            side_bays_max = 1,
            window_width_min = .75,
            window_width_max = 1.10,
            window_height_min = .75,
            window_height_max = 1.40,
            opening_ratio_min = 0,
            opening_ratio_max = .06,
            blank_sides = true,
            service = true,
        }
    }
    return {}
}

facade_profile_bay_count :: proc(
    profile: Facade_Profile,
    structure: terrain.Structure,
    face: Face,
    primary_face: bool,
    span: f32,
    wall_height: f32 = 0,
) -> int {
    low, high := profile.side_bays_min, profile.side_bays_max
    if face == .Rear {
        low, high = profile.rear_bays_min, profile.rear_bays_max
    } else if primary_face {
        low, high = profile.front_bays_min, profile.front_bays_max
    }
    if !primary_face && face != .Rear && !profile.blank_sides {
        low = max(low, 1)
    }
    if high <= 0 do return 0
    if primary_face && high >= 3 && span >= 28 do high = min(high + 1, 5)
    shift := u32(9 + int(face) * 3)
    face_multiplier := u32(0x9e3779b9) ~ (u32(int(face)) * u32(0x85ebca6b))
    low_seed := structure.seed & 255
    mixed := low_seed * face_multiplier
    folded := mixed ~ (mixed >> 8) ~ (mixed >> 16)
    // Retain the established high-bit slice while folding in low seed bits.
    // Small authored and capture seeds otherwise select the minimum bay count
    // on every face because all bits above bit eight are zero.
    variant := int(((structure.seed >> shift) ~ folded) & 255)
    count := low
    if high > low {
        count += variant % (high - low + 1)
    }
    count = int(math.floor(f64(f32(count) * ARCHITECTURE_WINDOW_DENSITY + .5)))
    if count > 0 && !profile.service && span >= 28 {
        // Archetype ranges describe ordinary façades, but using their fixed
        // maxima on very broad masses leaves the openings clustered around
        // the center because facade_bay_center caps pitch at 4.6 m. Add enough
        // bays to carry an existing rhythm across the usable wall instead.
        // A face that deliberately selected zero bays remains blank.
        usable_span := max(f32(0), span - 2 * 1.15 - profile.window_width_min)
        broad_face_count := int(math.ceil(f64(usable_span / 4.6))) + 1
        count = max(count, broad_face_count)
        if wall_height > 0 && profile.opening_ratio_min > 0 {
            window_width, window_height := facade_profile_window_size(profile, structure, face)
            rows := facade_profile_row_count(profile, wall_height, window_height)
            pane_area := window_width * window_height
            ground_factor := primary_face ? f32(.90 * .85) : f32(1)
            opening_area_per_column := pane_area * (f32(max(rows - 1, 0)) + ground_factor)
            if opening_area_per_column > .001 {
                // A centered entrance removes the middle ground pane whenever
                // the selected count is odd. Reserve one pane conservatively;
                // even counts may land slightly above the floor, never below.
                entrance_reserve := primary_face ? pane_area * ground_factor : f32(0)
                minimum_ratio_count := int(
                    math.ceil(
                        f64(
                            (profile.opening_ratio_min * span * wall_height + entrance_reserve) /
                            opening_area_per_column,
                        ),
                    ),
                )
                count = max(count, minimum_ratio_count)
                if profile.opening_ratio_max >= profile.opening_ratio_min {
                    maximum_ratio_count := int(
                        math.floor(
                            f64(
                                (profile.opening_ratio_max * span * wall_height + entrance_reserve) /
                                opening_area_per_column,
                            ),
                        ),
                    )
                    // A very narrow feasible interval can contain no integer
                    // bay count. In that case honor daylight minimum rather
                    // than forcing the wall below its profile floor.
                    if maximum_ratio_count >= minimum_ratio_count {
                        count = min(count, maximum_ratio_count)
                    }
                }
            }
        }
    }
    if count > 0 && !profile.service && span < 28 && wall_height > 0 && profile.opening_ratio_max > 0 {
        // On compact façades the archetype's seeded minimum bay count can be
        // denser than its own opening-ratio ceiling, especially when a cross
        // plan narrows a church frontage below the parcel width. Bound the
        // ordinary pane rhythm by actual wall area while retaining one bay
        // for daylight. Program-specific storefronts and arcades may override
        // this later because their minimum openings define the building use.
        window_width, window_height := facade_profile_window_size(profile, structure, face)
        rows := facade_profile_row_count(profile, wall_height, window_height)
        pane_area := window_width * window_height
        ground_factor := primary_face ? f32(.90 * .85) : f32(1)
        target_area := profile.opening_ratio_max * span * wall_height
        if pane_area > .001 {
            for count > 1 {
                ground_panes := count
                if primary_face && count % 2 == 1 do ground_panes -= 1
                estimated_area := pane_area * (f32(count * max(rows - 1, 0)) + f32(ground_panes) * ground_factor)
                if estimated_area <= target_area + .001 do break
                count -= 1
            }
        }
    }
    if primary_face && structure.building.archetype == .Mixed_Use_Dwelling && span < 42 {
        // Compact shops use a side door and one broad display pane. Ordinary
        // mixed-use frontage keeps the established door-between-two-panes
        // composition; only metropolitan-width bars repeat the rhythm.
        count = span < 14 ? 1 : 2
    }
    if primary_face && !profile.service do count = max(count, 1)
    minimum_gap := profile.rows_max > 0 ? f32(.95) : f32(1.15)
    maximum_fit := max(
        1,
        int(math.floor(f64((span - 2 * 1.15 + minimum_gap) / (profile.window_width_min + minimum_gap)))),
    )
    return clamp(count, 0, maximum_fit)
}

facade_profile_window_size :: proc(profile: Facade_Profile, structure: terrain.Structure, face: Face) -> (f32, f32) {
    face_multiplier := u32(0x9e3779b9) ~ (u32(int(face)) * u32(0x85ebca6b))
    mixed := (structure.seed & 255) * face_multiplier
    width_fold := mixed ~ (mixed >> 9) ~ (mixed >> 19)
    // Window widths may respond to each façade's proportions, but a shared
    // height module keeps sills and lintels aligned around building corners.
    height_mixed := (structure.seed & 255) * u32(0x85ebca6b)
    height_fold := (height_mixed >> 4) ~ (height_mixed >> 13) ~ (height_mixed >> 23)
    width_variant := (structure.seed >> u32(3 + int(face) * 2)) ~ width_fold
    height_variant := (structure.seed >> 5) ~ height_fold
    width_t := f32(width_variant & 31) / 31
    height_t := f32(height_variant & 31) / 31
    return profile.window_width_min + (profile.window_width_max - profile.window_width_min) * width_t,
        profile.window_height_min + (profile.window_height_max - profile.window_height_min) * height_t
}

facade_bay_center :: proc(span, window_width: f32, columns, column: int) -> f32 {
    if columns <= 1 do return 0
    usable_span := max(f32(0), span - 2 * 1.15 - window_width)
    // Sparse archetype profiles should remain sparse without collapsing into
    // a tight knot at the center of a broad wall. Carry the selected rhythm
    // across a useful portion of the elevation, while dense broad façades
    // retain their approximately 4.6 m cadence and corner clearance.
    occupied_span := min(usable_span, max(f32(columns - 1) * 4.6, span * .55))
    clamped_column := clamp(column, 0, columns - 1)
    if columns >= 7 && span >= 28 {
        // Broad elevations read as two inhabited wings around a civic or
        // domestic centre, rather than as one mechanically repeated grid.
        // Compress each half slightly and spend the recovered width on a
        // central breathing zone. The outermost bays remain fixed, so this
        // hierarchy does not trade away corner coverage or daylight area.
        ordinary_pitch := occupied_span / f32(columns - 1)
        centre_relief := min(f32(1.15), ordinary_pitch * .32)
        wing_span := max(f32(0), occupied_span - 2 * centre_relief)
        wing_pitch := wing_span / f32(columns - 1)
        centre := (f32(clamped_column) - f32(columns - 1) * .5) * wing_pitch
        if centre < -.001 {
            centre -= centre_relief
        } else if centre > .001 {
            centre += centre_relief
        }
        return centre
    }
    pitch := occupied_span / f32(columns - 1)
    return (f32(clamped_column) - f32(columns - 1) * .5) * pitch
}

facade_opening_row_count :: proc(height, opening_height: f32) -> int {
    desired := facade_floor_count(height)
    center_span := height - opening_height - 2 * 1.45
    if center_span <= 0 do return 1
    // Leave a visible strip of wall/trim between vertically adjacent panes.
    maximum_fit := int(math.floor(f64(center_span / (opening_height + .35)))) + 1
    return clamp(desired, 1, max(maximum_fit, 1))
}

facade_profile_row_count :: proc(profile: Facade_Profile, height, opening_height: f32) -> int {
    rows := facade_opening_row_count(height, opening_height)
    if profile.rows_max > 0 do rows = min(rows, profile.rows_max)
    return rows
}

facade_opening_row_y_for_count :: proc(height: f32, row, rows: int, opening_height: f32) -> f32 {
    first_y := opening_height * .5 + 1.45
    if rows <= 1 do return first_y
    last_y := max(first_y, height - opening_height * .5 - 1.45)
    return first_y + (last_y - first_y) * f32(clamp(row, 0, rows - 1)) / f32(rows - 1)
}

facade_opening_row_pitch :: proc(height: f32, rows: int, opening_height: f32) -> f32 {
    if rows <= 1 do return 0
    first_y := opening_height * .5 + 1.45
    last_y := max(first_y, height - opening_height * .5 - 1.45)
    return (last_y - first_y) / f32(rows - 1)
}

facade_opening_row_count_for_pitch :: proc(height, opening_height: f32, desired_rows: int, pitch: f32) -> int {
    if desired_rows <= 1 || pitch <= 0 do return 1
    first_y := opening_height * .5 + 1.45
    maximum_center := height - opening_height * .5 - .75
    if maximum_center <= first_y do return 1
    maximum_fit := int(math.floor(f64((maximum_center - first_y) / pitch))) + 1
    return clamp(desired_rows, 1, max(maximum_fit, 1))
}

facade_opening_row_y_for_pitch :: proc(row: int, opening_height, pitch: f32) -> f32 {
    return opening_height * .5 + 1.45 + f32(max(row, 0)) * pitch
}

facade_opening_row_y :: proc(height: f32, row: int, opening_height: f32) -> f32 {
    rows := facade_opening_row_count(height, opening_height)
    return facade_opening_row_y_for_count(height, row, rows, opening_height)
}

LIGHTHOUSE_SHAFT_DRUM_COUNT :: 5
LIGHTHOUSE_SLIT_COUNT :: 3

lighthouse_slit_height_fraction :: proc(level: int) -> f32 {
    // Keep the first slit well above the keeper door, then follow the internal
    // stair with an even vertical cadence through the occupied shaft.
    return .34 + f32(clamp(level, 0, LIGHTHOUSE_SLIT_COUNT - 1)) * .19
}

lighthouse_shaft_radius_scale :: proc(height_fraction: f32) -> f32 {
    drum := clamp(
        int(math.floor(f64(clamp(height_fraction, f32(0), f32(.9999)) * LIGHTHOUSE_SHAFT_DRUM_COUNT))),
        0,
        LIGHTHOUSE_SHAFT_DRUM_COUNT - 1,
    )
    return 1 - f32(drum) * .055
}

// Compound footprints are assembled from overlapping rectangular masses. A
// face can therefore be geometrically valid for one mass while sitting inside
// an attached wing. Suppress openings whose wall segment intersects another
// mass; otherwise windows and vents appear embedded in the join between roofs.
ARCHITECTURE_ATTACHED_EAVE_PLAN_MARGIN_FACTOR :: f32(.05)
ARCHITECTURE_ATTACHED_EAVE_VERTICAL_CLEARANCE :: f32(.30)

architecture_opening_occluded_by_mass :: proc(
    footprint: Architecture_Footprint,
    mass_index: int,
    face: Face,
    horizontal, y, width, height, structure_height: f32,
) -> bool {
    if mass_index < 0 || mass_index >= footprint.count do return false
    mass := footprint.masses[mass_index]
    opening_min_y, opening_max_y := y - height * .5, y + height * .5
    face_coordinate: f32
    opening_min, opening_max: f32
    switch face {
    case .Front:
        face_coordinate = mass.local_z + mass.depth * .5
        opening_min = mass.local_x + horizontal - width * .5
        opening_max = mass.local_x + horizontal + width * .5
    case .Rear:
        face_coordinate = mass.local_z - mass.depth * .5
        opening_min = mass.local_x - horizontal - width * .5
        opening_max = mass.local_x - horizontal + width * .5
    case .Left:
        face_coordinate = mass.local_x - mass.width * .5
        opening_min = mass.local_z + horizontal - width * .5
        opening_max = mass.local_z + horizontal + width * .5
    case .Right:
        face_coordinate = mass.local_x + mass.width * .5
        opening_min = mass.local_z - horizontal - width * .5
        opening_max = mass.local_z - horizontal + width * .5
    }

    epsilon: f32 = .001
    for other_index in 0 ..< footprint.count {
        if other_index == mass_index do continue
        other := footprint.masses[other_index]
        other_height := max(f32(0), structure_height * other.height_scale)
        body_vertical_overlap := opening_max_y > epsilon && opening_min_y < other_height - epsilon
        eave_vertical_overlap :=
            opening_max_y > other_height - ARCHITECTURE_ATTACHED_EAVE_VERTICAL_CLEARANCE &&
            opening_min_y < other_height + ARCHITECTURE_ATTACHED_EAVE_VERTICAL_CLEARANCE
        if !body_vertical_overlap && !eave_vertical_overlap do continue
        if face == .Front || face == .Rear {
            other_min := other.local_x - other.width * .5
            other_max := other.local_x + other.width * .5
            inside_depth :=
                face_coordinate >= other.local_z - other.depth * .5 - epsilon &&
                face_coordinate <= other.local_z + other.depth * .5 + epsilon
            if body_vertical_overlap &&
               inside_depth &&
               opening_max > other_min + epsilon &&
               opening_min < other_max - epsilon {
                return true
            }
            eave_margin_x := other.width * ARCHITECTURE_ATTACHED_EAVE_PLAN_MARGIN_FACTOR
            eave_margin_z := other.depth * ARCHITECTURE_ATTACHED_EAVE_PLAN_MARGIN_FACTOR
            inside_eave_depth :=
                face_coordinate >= other.local_z - other.depth * .5 - eave_margin_z - epsilon &&
                face_coordinate <= other.local_z + other.depth * .5 + eave_margin_z + epsilon
            if eave_vertical_overlap &&
               inside_eave_depth &&
               opening_max > other_min - eave_margin_x + epsilon &&
               opening_min < other_max + eave_margin_x - epsilon {
                return true
            }
        } else {
            other_min := other.local_z - other.depth * .5
            other_max := other.local_z + other.depth * .5
            inside_width :=
                face_coordinate >= other.local_x - other.width * .5 - epsilon &&
                face_coordinate <= other.local_x + other.width * .5 + epsilon
            if body_vertical_overlap &&
               inside_width &&
               opening_max > other_min + epsilon &&
               opening_min < other_max - epsilon {
                return true
            }
            eave_margin_x := other.width * ARCHITECTURE_ATTACHED_EAVE_PLAN_MARGIN_FACTOR
            eave_margin_z := other.depth * ARCHITECTURE_ATTACHED_EAVE_PLAN_MARGIN_FACTOR
            inside_eave_width :=
                face_coordinate >= other.local_x - other.width * .5 - eave_margin_x - epsilon &&
                face_coordinate <= other.local_x + other.width * .5 + eave_margin_x + epsilon
            if eave_vertical_overlap &&
               inside_eave_width &&
               opening_max > other_min - eave_margin_z + epsilon &&
               opening_min < other_max + eave_margin_z - epsilon {
                return true
            }
        }
    }
    return false
}

architecture_exposed_face_area :: proc(
    footprint: Architecture_Footprint,
    mass_index: int,
    face: Face,
    structure_height: f32,
) -> f32 {
    if mass_index < 0 || mass_index >= footprint.count do return 0
    mass := footprint.masses[mass_index]
    wall_height := max(f32(0), structure_height * mass.height_scale)
    span := face_span(mass, face)
    total_area := span * wall_height
    if total_area <= 0 do return 0

    face_coordinate: f32
    face_min, face_max: f32
    if face == .Front || face == .Rear {
        face_coordinate = mass.local_z + (face == .Front ? mass.depth * .5 : -mass.depth * .5)
        face_min, face_max = mass.local_x - mass.width * .5, mass.local_x + mass.width * .5
    } else {
        face_coordinate = mass.local_x + (face == .Right ? mass.width * .5 : -mass.width * .5)
        face_min, face_max = mass.local_z - mass.depth * .5, mass.local_z + mass.depth * .5
    }

    occluder_min, occluder_max: [2]f32
    occluder_height: [2]f32
    occluder_count := 0
    epsilon: f32 = .001
    for other_index in 0 ..< footprint.count {
        if other_index == mass_index || occluder_count >= 2 do continue
        other := footprint.masses[other_index]
        interval_min, interval_max: f32
        crosses_face := false
        if face == .Front || face == .Rear {
            crosses_face =
                face_coordinate >= other.local_z - other.depth * .5 - epsilon &&
                face_coordinate <= other.local_z + other.depth * .5 + epsilon
            interval_min = max(face_min, other.local_x - other.width * .5)
            interval_max = min(face_max, other.local_x + other.width * .5)
        } else {
            crosses_face =
                face_coordinate >= other.local_x - other.width * .5 - epsilon &&
                face_coordinate <= other.local_x + other.width * .5 + epsilon
            interval_min = max(face_min, other.local_z - other.depth * .5)
            interval_max = min(face_max, other.local_z + other.depth * .5)
        }
        if !crosses_face || interval_max <= interval_min + epsilon do continue
        occluder_min[occluder_count] = interval_min
        occluder_max[occluder_count] = interval_max
        occluder_height[occluder_count] = min(wall_height, max(f32(0), structure_height * other.height_scale))
        occluder_count += 1
    }

    covered_area := f32(0)
    for index in 0 ..< occluder_count {
        covered_area += (occluder_max[index] - occluder_min[index]) * occluder_height[index]
    }
    if occluder_count == 2 {
        shared_min := max(occluder_min[0], occluder_min[1])
        shared_max := min(occluder_max[0], occluder_max[1])
        if shared_max > shared_min {
            // Inclusion-exclusion prevents nested or overlapping attachments
            // from subtracting the same buried wall patch twice.
            covered_area -= (shared_max - shared_min) * min(occluder_height[0], occluder_height[1])
        }
    }
    return max(f32(0), total_area - covered_area)
}
