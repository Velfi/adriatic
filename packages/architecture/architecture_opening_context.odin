package architecture

import buildings "../buildings"
import terrain "../terrain"
import "core:math"

architecture_opening_layout_add_habitable_row_on_face :: proc(
    layout: ^Opening_Layout,
    footprint: Architecture_Footprint,
    structure: terrain.Structure,
    mass_index: int,
    profile: Facade_Profile,
    face: Face,
    row: int,
) -> bool {
    if layout == nil || mass_index < 0 || mass_index >= footprint.count || row < 0 do return false
    mass := footprint.masses[mass_index]
    wall_height := max(f32(0), structure.height * mass.height_scale)
    span := face_span(mass, face)
    if span < ARCHITECTURE_MIN_OPENING_FACE_SPAN do return false
    profile_face := architecture_paired_profile_face(footprint, mass_index, face)
    window_width, window_height := facade_profile_window_size(profile, structure, profile_face)
    storey_rows := facade_floor_count(wall_height)
    if profile.rows_max > 0 do storey_rows = min(storey_rows, profile.rows_max)
    if storey_rows > 1 {
        fitted_window_height := (wall_height - 2 * 1.45 - f32(storey_rows - 1) * .35) / f32(storey_rows)
        window_height = min(window_height, max(f32(.75), fitted_window_height - .01))
    }
    independent_range_pitch :=
        (structure.building.archetype == .Farmstead &&
            footprint.count == 2 &&
            mass_index == 1 &&
            structure.width >= 20 &&
            structure.depth >= 18 &&
            structure.seed % 5 == 0) ||
        (structure.building.archetype == .Shop_House &&
                footprint.count == 2 &&
                mass_index == 1 &&
                structure.width >= 16 &&
                structure.depth >= 14 &&
                structure.seed % 4 == 0) ||
        (structure.building.archetype == .Post_Office && mass_index > 0)
    reference_height := independent_range_pitch ? wall_height : structure.height
    reference_rows := facade_profile_row_count(profile, reference_height, window_height)
    reference_pitch := facade_opening_row_pitch(reference_height, reference_rows, window_height)
    desired_rows := facade_profile_row_count(profile, wall_height, window_height)
    fitted_rows := facade_opening_row_count_for_pitch(wall_height, window_height, desired_rows, reference_pitch)
    if fitted_rows < desired_rows && desired_rows > 1 {
        // Preserve the parent datum while it represents every occupied level.
        // Near the one/two-storey threshold a shortened wing can physically
        // fit two rows but not the taller parent's second sill; use the wing's
        // own complete rhythm instead of silently deleting its upper floor.
        reference_pitch = facade_opening_row_pitch(wall_height, desired_rows, window_height)
        fitted_rows = desired_rows
    }
    if row >= fitted_rows do return false
    opening_y := facade_opening_row_y_for_pitch(row, window_height, reference_pitch)
    fitted_widths := [2]f32{window_width, min(window_width, f32(.55))}
    for fitted_width in fitted_widths {
        edge_center := max(f32(0), span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN - fitted_width * .5)
        centers: [21]f32
        centers[0], centers[1], centers[2], centers[3], centers[4] =
            0, -span * .25, span * .25, -edge_center, edge_center
        // The first five candidates preserve the compact fallback grammar.
        // A supplementary 16-point grid lets repeated calls populate a broad
        // exposed strip after an attachment culls the originally seeded bays.
        for grid_column in 0 ..< 16 {
            centers[5 + grid_column] = -edge_center + 2 * edge_center * f32(grid_column) / 15
        }
        for horizontal in centers {
            if math.abs(horizontal) + fitted_width * .5 > span * .5 - ARCHITECTURE_OPENING_CORNER_MARGIN {
                continue
            }
            if opening_layout_conflicts_with_door(layout, face, horizontal, opening_y, fitted_width, window_height) {
                continue
            }
            if architecture_opening_occluded_by_mass(
                footprint,
                mass_index,
                face,
                horizontal,
                opening_y,
                fitted_width,
                window_height,
                structure.height,
            ) {
                continue
            }
            if opening_layout_conflicts_with_opening(
                layout,
                face,
                horizontal,
                opening_y,
                fitted_width,
                window_height,
            ) {
                continue
            }
            logical_column := 0
            for existing in layout.openings[:layout.count] {
                if existing.face == face && existing.kind == .Window && existing.row == row {
                    logical_column = max(logical_column, existing.column + 1)
                }
            }
            return opening_layout_add(
                layout,
                {
                    face = face,
                    kind = .Window,
                    horizontal = horizontal,
                    y = opening_y,
                    width = fitted_width,
                    height = window_height,
                    row = row,
                    column = logical_column,
                },
            )
        }
    }
    return false
}

architecture_opening_layout_add_habitable_row_fallback :: proc(
    layout: ^Opening_Layout,
    footprint: Architecture_Footprint,
    structure: terrain.Structure,
    mass_index: int,
    profile: Facade_Profile,
    row: int,
) -> bool {
    fallback_faces := [4]Face{.Front, .Left, .Right, .Rear}
    for face in fallback_faces {
        if architecture_opening_layout_add_habitable_row_on_face(
            layout,
            footprint,
            structure,
            mass_index,
            profile,
            face,
            row,
        ) {
            return true
        }
    }
    return false
}

opening_layout_reindex_window_columns :: proc(layout: ^Opening_Layout) {
    if layout == nil do return
    row_counts: [4][16]int
    row_offsets: [4][16]int
    row_cursors: [4][16]int
    row_indices: [OPENING_LAYOUT_CAPACITY]int
    for opening in layout.openings[:layout.count] {
        if opening.kind != .Window || opening.row < 0 || opening.row >= 16 do continue
        row_counts[int(opening.face)][opening.row] += 1
    }
    offset := 0
    for face_index in 0 ..< 4 {
        for row in 0 ..< 16 {
            row_offsets[face_index][row] = offset
            row_cursors[face_index][row] = offset
            offset += row_counts[face_index][row]
        }
    }
    for opening, opening_index in layout.openings[:layout.count] {
        if opening.kind != .Window || opening.row < 0 || opening.row >= 16 do continue
        face_index := int(opening.face)
        cursor := row_cursors[face_index][opening.row]
        row_indices[cursor] = opening_index
        row_cursors[face_index][opening.row] += 1
    }
    for face_index in 0 ..< 4 {
        for row in 0 ..< 16 {
            row_count := row_counts[face_index][row]
            row_offset := row_offsets[face_index][row]
            // Rows rarely exceed a few dozen panes. Sorting each compact row
            // after two linear gathering passes retains stable order for equal
            // coordinates without rescanning the full layout per face/row.
            for index in 1 ..< row_count {
                opening_index := row_indices[row_offset + index]
                insert_at := index
                for insert_at > 0 &&
                    layout.openings[row_indices[row_offset + insert_at - 1]].horizontal >
                        layout.openings[opening_index].horizontal {
                    row_indices[row_offset + insert_at] = row_indices[row_offset + insert_at - 1]
                    insert_at -= 1
                }
                row_indices[row_offset + insert_at] = opening_index
            }
            for opening_index, spatial_column in row_indices[row_offset:row_offset + row_count] {
                layout.openings[opening_index].column = spatial_column
            }
        }
    }
}

Architecture_Opening_Face_Context :: struct {
    structure:                   terrain.Structure,
    footprint:                   Architecture_Footprint,
    mass:                        Architecture_Mass,
    identity:                    buildings.Identity,
    profile:                     Facade_Profile,
    wall_height:                 f32,
    mass_index:                  int,
    farmstead_work_range:        bool,
    shop_stock_range:            bool,
    post_sorting_range:          bool,
    clinic_ward_range:           bool,
    fortress_tower:              bool,
    fortress_guard_range:        bool,
    bell_tower:                  bool,
    mill_tower:                  bool,
    barn_range:                  bool,
    workshop_daylight:           bool,
    fishery_work_hall:           bool,
    storehouse_high_vents:       bool,
    harbor_dispatch_range:       bool,
    harbor_service_range:        bool,
    habitable:                   bool,
    occupied_secondary_daylight: bool,
    storehouse_loading_range:    bool,
    fishery_smokehouse_range:    bool,
    market_loading_range:        bool,
    market_basilica_aisle:       bool,
    market_basilica_nave:        bool,
    monastery_cloister_range:    bool,
    primary_mass:                bool,
    mixed_use_apartment_face:    Face,
}
