package main
import "core:math"

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import canvas2d "zelda_engine:canvas2d"

world_architecture_mass :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    has_entrance: bool = true,
    opening_layout: ^architecture.Opening_Layout = nil,
    lod: Structure_LOD = .Near,
) {
    identity := architecture.architecture_resolve_legacy_identity(structure)
    habitable := buildings.is_habitable(identity.archetype)
    mixed_use := identity.archetype == .Mixed_Use_Dwelling
    landmark := structure.height > 60 || settlement_structure_is_landmark(structure) || buildings.is_landmark(identity)
    facade_style := architecture.facade_style_for_seed(structure.seed)
    roof_style := world_architecture_roof_style(structure)
    stone := canvas2d.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    aegean := identity.region == .Aegean
    ground_stone := formation_face_color(stone, f32((structure.seed >> 10) & 3) * .10 - .15, 0)
    if aegean {
        // Cycladic walls are whitewashed to the ground. Passing their pale
        // wall color through the facet shader twice produced a continuous
        // charcoal lower storey, making dense villages read as bunkers.
        ground_stone = stone
    }
    // The masonry base and stucco upper storeys are separate, disjoint hulls.
    // Previously a slightly enlarged masonry box covered the lower portion of
    // one full-height stucco box, leaving two competing wall surfaces. Give
    // each material exclusive ownership of its vertical range instead.
    masonry_height := min(structure.height, aegean ? f32(.68) : f32(2.90))
    world_architecture_box_rotated(
        {structure.center_x, structure.base_y + masonry_height * .5, structure.center_z},
        {structure.width, masonry_height, structure.depth},
        structure.rotation,
        ground_stone,
        1,
    )
    upper_height := structure.height - masonry_height
    if upper_height > .001 {
        world_architecture_box_rotated(
            {structure.center_x, structure.base_y + masonry_height + upper_height * .5, structure.center_z},
            {structure.width, upper_height, structure.depth},
            structure.rotation,
            stone,
        )
    }
    // A shallow overhanging limestone plinth separates each façade from the
    // terrain and gives the compact blocks a believable masonry foundation.
    plinth := formation_face_color(stone, math.PI, 0)
    plinth_height := .52 + f32((structure.seed >> 7) % 4) * .05
    foundation_low, _ := architecture.architecture_mass_height_range(project, structure)
    foundation_depth := max(structure.base_y - foundation_low + .18, f32(0))
    if foundation_depth > .01 {
        foundation_color := formation_face_color(plinth, math.PI * .45, 0)
        world_architecture_box_rotated(
            {structure.center_x, structure.base_y - foundation_depth * .5 + .02, structure.center_z},
            {structure.width + .30, foundation_depth + .04, structure.depth + .30},
            structure.rotation,
            foundation_color,
            1,
        )
    }
    world_architecture_box_rotated(
        {structure.center_x, structure.base_y + plinth_height * .5, structure.center_z},
        {structure.width + .46, plinth_height, structure.depth + .46},
        structure.rotation,
        plinth,
        1,
    )
    damp_course :=
        facade_style == 2 ? canvas2d.Color{92, 113, 110, 255} : facade_style == 3 ? canvas2d.Color{139, 107, 83, 255} : formation_face_color(plinth, math.PI, 0)
    world_architecture_box_rotated(
        {structure.center_x, structure.base_y + plinth_height + .06, structure.center_z},
        {structure.width + .22, .12, structure.depth + .22},
        structure.rotation,
        damp_course,
    )
    if lod == .Far {
        world_architecture_roof(structure, landmark, lod, has_entrance)
        panel := formation_face_color(stone, math.PI, 0)
        panel_width := clamp(structure.width * .42, f32(2.4), structure.width * .72)
        panel_height := clamp(structure.height * .26, f32(2.4), f32(6.0))
        panel_x, panel_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .07,
            structure.rotation,
        )
        world_box_rotated(
            {panel_x, structure.base_y + structure.height * .48, panel_z},
            {panel_width, panel_height, .12},
            structure.rotation,
            panel,
        )
        return
    }
    if opening_layout != nil {
        stoop_color := formation_face_color(plinth, math.PI * .18, 0)
        for opening in opening_layout.openings[:opening_layout.count] {
            world_architecture_door_stoop(structure, project, opening, stoop_color)
        }
    }
    if !landmark {
        for corner_side in -1 ..= 1 {
            if corner_side == 0 do continue
            corner_x, corner_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(corner_side) * (structure.width * .5 - .28),
                structure.depth * .5 + .20,
                structure.rotation,
            )
            world_box_rotated(
                {corner_x, structure.base_y + .43, corner_z},
                {.56, .86, .20},
                structure.rotation,
                formation_face_color(plinth, f32(corner_side) * .25, 0),
            )
        }
        if structure.width >= 18 && structure.seed % 3 == 0 {
            for vent_side in -1 ..= 1 {
                if vent_side == 0 do continue
                vent_x, vent_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    f32(vent_side) * structure.width * .30,
                    structure.depth * .5 + .25,
                    structure.rotation,
                )
                world_box_rotated(
                    {vent_x, structure.base_y + .32, vent_z},
                    {.52, .20, .08},
                    structure.rotation,
                    {62, 69, 66, 255},
                )
            }
        }
        utility_side := (structure.seed & 2) == 0 ? f32(-1) : f32(1)
        utility_offset := max(structure.width * .5 - .82, f32(2.4))
        utility_local_x := utility_side * utility_offset
        pipe_x, pipe_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            utility_local_x,
            structure.depth * .5 + .24,
            structure.rotation,
        )
        // Carry the downspout all the way to the eave. Capping this detail at
        // 10.4 m left it visibly stranded midway up taller façades.
        world_box_rotated(
            {pipe_x, structure.base_y + structure.height * .5, pipe_z},
            {.13, structure.height, .13},
            structure.rotation,
            {82, 83, 76, 255},
        )
        shoe_x, shoe_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            utility_local_x - utility_side * .16,
            structure.depth * .5 + .36,
            structure.rotation,
        )
        world_box_rotated(
            {shoe_x, structure.base_y + .20, shoe_z},
            {.42, .16, .30},
            structure.rotation,
            {72, 73, 67, 255},
        )
        box_x, box_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            -utility_local_x,
            structure.depth * .5 + .27,
            structure.rotation,
        )
        box_y := structure.base_y + 1.05
        world_box_rotated({box_x, box_y, box_z}, {.62, .72, .16}, structure.rotation, {113, 119, 111, 255})
        world_box_rotated({box_x, box_y + 1.25, box_z - .02}, {.08, 1.80, .10}, structure.rotation, {96, 101, 94, 255})
        if structure.seed % 4 == 0 {
            patch_side := utility_side
            patch_x, patch_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                patch_side * structure.width * .24,
                structure.depth * .5 + .145,
                structure.rotation,
            )
            patch_color := formation_face_color(stone, patch_side * .18, 0)
            world_box_rotated(
                {patch_x, structure.base_y + 1.45, patch_z},
                {1.25, .72, .035},
                structure.rotation,
                patch_color,
            )
        }
        gravel := canvas2d.Color{136, 126, 108, 255}
        gravel_x, gravel_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .43,
            structure.rotation,
        )
        world_box_rotated(
            {gravel_x, structure.base_y + .025, gravel_z},
            {structure.width + .70, .05, .34},
            structure.rotation,
            gravel,
        )
        for side in -1 ..= 1 {
            if side == 0 do continue
            side_gravel_x, side_gravel_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(side) * (structure.width * .5 + .39),
                0,
                structure.rotation,
            )
            world_box_rotated(
                {side_gravel_x, structure.base_y + .025, side_gravel_z},
                {structure.depth + .70, .05, .28},
                structure.rotation + math.PI * .5,
                gravel,
            )
        }
    }
    if !landmark && facade_style == 3 {
        wing_x, wing_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            structure.width * .28,
            -structure.depth * .05,
            structure.rotation,
        )
        wing_height := structure.height * .44
        world_architecture_box_rotated(
            {wing_x, structure.base_y + wing_height * .5, wing_z},
            {structure.width * .38, wing_height, structure.depth * .72},
            structure.rotation,
            stone,
        )
        world_box_rotated(
            {wing_x, structure.base_y + wing_height + .18, wing_z},
            {structure.width * .42, .36, structure.depth * .78},
            structure.rotation,
            {184, 93, 61, 255},
        )
    }
    world_architecture_roof(structure, landmark, lod, has_entrance)
    if lod == .Medium {
        window := facade_style == 2 ? canvas2d.Color{42, 74, 82, 255} : canvas2d.Color{48, 62, 64, 255}
        rows := architecture.facade_floor_count(structure.height)
        if opening_layout != nil {
            for opening in opening_layout.openings[:opening_layout.count] {
                if opening.face != .Front || opening.kind != .Window do continue
                local_x := opening.horizontal
                window_y := structure.base_y + opening.y
                window_width := opening.width
                window_height := opening.height
                window_x, window_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    local_x,
                    structure.depth * .5 + .08,
                    structure.rotation,
                )
                world_box_rotated(
                    {window_x, window_y, window_z},
                    {window_width, window_height, .14},
                    structure.rotation,
                    window,
                )
                // Even at medium LOD, split the opening into glazed panes so
                // it reads as a window rather than a black square.
                glass := facade_style == 2 ? canvas2d.Color{55, 94, 104, 255} : canvas2d.Color{57, 80, 83, 255}
                frame := facade_style == 2 ? canvas2d.Color{170, 181, 166, 255} : canvas2d.Color{174, 158, 134, 255}
                glass_x, glass_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    local_x,
                    structure.depth * .5 + .16,
                    structure.rotation,
                )
                storefront_window :=
                    opening.row == 0 &&
                    (identity.archetype == .Shop_House || identity.archetype == .Mixed_Use_Dwelling)
                interior, interior_light := world_architecture_window_interior(
                    structure,
                    opening.face,
                    opening.row,
                    opening.column,
                    storefront_window,
                )
                if interior_light > 0 do glass = interior
                world_glass_panel(
                    {glass_x, window_y, glass_z},
                    window_width * .84,
                    window_height * .82,
                    structure.rotation,
                    glass,
                    interior_light,
                    world_architecture_window_room(structure, opening.face, opening.row, opening.column),
                )
                world_box_rotated(
                    {glass_x, window_y, glass_z},
                    {.055, window_height * .82, .035},
                    structure.rotation,
                    frame,
                )
                world_box_rotated(
                    {glass_x, window_y + window_height * .08, glass_z},
                    {window_width * .84, .05, .035},
                    structure.rotation,
                    frame,
                )
            }
        }
        if has_entrance && habitable {
            door_width := clamp(structure.width * .13, f32(1.8), f32(2.8))
            door_height := clamp(structure.height * .075, f32(3.0), f32(4.0))
            door_y := door_height * .5
            if opening, found := architecture.opening_layout_find(opening_layout, .Front, .Door, 0, 0); found {
                door_width, door_height, door_y = opening.width, opening.height, opening.y
            }
            door_x, door_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .10,
                structure.rotation,
            )
            world_box_rotated(
                {door_x, structure.base_y + door_y, door_z},
                {door_width, door_height, .16},
                structure.rotation,
                {92, 66, 57, 255},
            )
        }
        if !landmark && rows > 1 && structure.seed % 3 == 0 && opening_layout != nil {
            balcony_opening: ^architecture.Opening
            for opening, index in opening_layout.openings[:opening_layout.count] {
                if opening.face != .Front || opening.kind != .Window || opening.row != rows - 1 do continue
                if balcony_opening == nil || math.abs(opening.horizontal) < math.abs(balcony_opening.horizontal) {
                    balcony_opening = &opening_layout.openings[index]
                }
            }
            if balcony_opening != nil {
                balcony_x, balcony_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    balcony_opening.horizontal,
                    structure.depth * .5 + .42,
                    structure.rotation,
                )
                balcony_y := structure.base_y + balcony_opening.y - balcony_opening.height * .5
                world_box_rotated(
                    {balcony_x, balcony_y, balcony_z},
                    {balcony_opening.width + 1.35, .14, .72},
                    structure.rotation,
                    {111, 94, 76, 255},
                )
            }
        }
        face_trim :=
            facade_style == 2 ? canvas2d.Color{166, 171, 151, 255} : (facade_style == 1 ? canvas2d.Color{205, 190, 157, 255} : canvas2d.Color{190, 166, 128, 255})
        world_architecture_face_openings(structure, opening_layout, window, face_trim)
        return
    }
    // Dark inset windows and red shutters give the generated blocks a readable
    // Adriatic façade even at the editor's wide camera distance.
    window := facade_style == 2 ? canvas2d.Color{42, 74, 82, 255} : canvas2d.Color{48, 62, 64, 255}
    shutter :=
        facade_style == 2 ? canvas2d.Color{43, 102, 126, 255} : facade_style == 3 ? canvas2d.Color{236, 218, 179, 255} : canvas2d.Color{167, 61, 53, 255}
    world_architecture_entrance(
        structure,
        project,
        opening_layout,
        identity,
        stone,
        has_entrance,
        habitable,
        mixed_use,
        facade_style,
    )
    world_architecture_mixed_use_entrances(structure, project, opening_layout, mixed_use, has_entrance, facade_style)
    rich_front := habitable
    storefront_front := identity.archetype == .Shop_House || identity.archetype == .Mixed_Use_Dwelling
    if has_entrance && storefront_front && lod == .Near {
        spill_x, spill_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + 2.15,
            structure.rotation,
        )
        spill_ground := terrain.sample_surface_height(project, 0, spill_x, spill_z)
        spill_sample_distance := f32(2)
        spill_slope_x := clamp(
            (terrain.sample_surface_height(project, 0, spill_x + spill_sample_distance, spill_z) - spill_ground) /
            spill_sample_distance,
            f32(-.35),
            f32(.35),
        )
        spill_slope_z := clamp(
            (terrain.sample_surface_height(project, 0, spill_x, spill_z + spill_sample_distance) - spill_ground) /
            spill_sample_distance,
            f32(-.35),
            f32(.35),
        )
        world_ellipse_material_uv(
            {spill_x, spill_ground + .225, spill_z},
            min(structure.width * .38, f32(5.5)),
            3.4,
            structure.rotation,
            {255, 174, 72, 34},
            .Emissive_Pool,
            spill_slope_x,
            spill_slope_z,
            1,
        )
    }
    world_architecture_front_windows(
        structure,
        opening_layout,
        window,
        shutter,
        rich_front,
        storefront_front,
        mixed_use,
        landmark,
        facade_style,
    )
    face_trim :=
        facade_style == 2 ? canvas2d.Color{166, 171, 151, 255} : (facade_style == 1 ? canvas2d.Color{205, 190, 157, 255} : canvas2d.Color{190, 166, 128, 255})
    world_architecture_face_openings(structure, opening_layout, window, face_trim)
    // Climbing foliage is authored exclusively through the density brush;
    // keep the legacy always-on planter vine disabled so it cannot overlap
    // the simulated growth with a second, unrelated stem.
    if false {
        // A small bougainvillea climbs from one planter. Keep the stem close
        // to the wall and use individual leaf pairs so it reads as a vine,
        // not as floating topiary attached to the façade.
        vine_side := structure.seed % 2 == 0 ? -1 : 1
        vine_z_local := structure.depth * .5 + .39
        vine_x_base := f32(vine_side) * structure.width * .36
        vine_bottom := structure.base_y + structure.height * .14
        vine_top := structure.base_y + structure.height * .72
        planter_x, planter_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            vine_x_base,
            vine_z_local + .04,
            structure.rotation,
        )
        world_box_rotated(
            {planter_x, vine_bottom - .06, planter_z},
            {.62, .28, .42},
            structure.rotation,
            {164, 91, 62, 255},
        )
        stem_x, stem_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            vine_x_base,
            vine_z_local,
            structure.rotation,
        )
        world_box_rotated(
            {stem_x, (vine_bottom + vine_top) * .5, stem_z},
            {.07, vine_top - vine_bottom, .06},
            structure.rotation,
            {72, 119, 62, 255},
        )
        for segment in 0 ..< 7 {
            start_t := f32(segment) / 7
            end_t := f32(segment + 1) / 7
            start_x :=
                vine_x_base + f32(math.sin(f64(f32(structure.seed + u32(segment)) * .47))) * structure.width * .035
            end_x :=
                vine_x_base + f32(math.sin(f64(f32(structure.seed + u32(segment + 1)) * .47))) * structure.width * .035
            start_y := vine_bottom + (vine_top - vine_bottom) * start_t
            end_y := vine_bottom + (vine_top - vine_bottom) * end_t
            if segment % 2 == 1 {
                branch_x, branch_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    end_x + f32(vine_side) * structure.width * .035,
                    vine_z_local + .035,
                    structure.rotation,
                )
                world_box_rotated(
                    {branch_x, end_y, branch_z},
                    {.30, .045, .045},
                    structure.rotation,
                    {72, 119, 62, 255},
                )
                leaf_x, leaf_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    end_x + f32(vine_side) * structure.width * .07,
                    vine_z_local + .02,
                    structure.rotation,
                )
                world_ellipsoid_rotated({leaf_x, end_y, leaf_z}, .38, .13, .22, structure.rotation, {63, 117, 62, 255})
                second_leaf_x, second_leaf_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    end_x - f32(vine_side) * structure.width * .055,
                    vine_z_local + .04,
                    structure.rotation,
                )
                world_ellipsoid_rotated(
                    {second_leaf_x, end_y - .06, second_leaf_z},
                    .30,
                    .11,
                    .18,
                    structure.rotation,
                    {78, 133, 70, 255},
                )
            }
            if segment == 2 || segment == 5 {
                bloom_x, bloom_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    end_x + f32(vine_side) * structure.width * .085,
                    vine_z_local + .05,
                    structure.rotation,
                )
                world_ellipsoid_rotated(
                    {bloom_x, end_y + .02, bloom_z},
                    .18,
                    .14,
                    .16,
                    structure.rotation,
                    {214, 82, 112, 255},
                )
            }
        }
    }
    if !landmark && (roof_style == .Gable || roof_style == .Low_Gable) {
        low_gable := roof_style == .Low_Gable
        // Pitched roofs normalize the footprint into a long-axis frame before
        // placing the ridge. Use that same frame for the attic windows so
        // they stay on the gable ends when the roof rotates.
        roof_width, roof_depth, roof_rotation := world_roof_long_axis_frame(
            structure.width,
            structure.depth,
            structure.rotation,
        )
        attic_width, attic_height, rise, center_fraction, valid := world_gable_attic_opening_plan(
            roof_width,
            low_gable,
        )
        if valid {
            attic_y := structure.base_y + structure.height + rise * center_fraction
            frame_width := clamp(min(attic_width, attic_height) * .10, f32(.09), f32(.15))
            frame_color :=
                identity.region == .Aegean ? canvas2d.Color{237, 232, 210, 255} : canvas2d.Color{190, 166, 128, 255}
            mullion_color := formation_face_color(frame_color, math.PI, 0)
            pane_color := facade_style == 2 ? canvas2d.Color{59, 96, 105, 255} : canvas2d.Color{55, 78, 82, 255}
            for gable_end in -1 ..= 1 {
                if gable_end == 0 do continue
                local_z := f32(gable_end) * (roof_depth * .58 + .12)
                attic_x, attic_z := world_rotate_xz(structure.center_x, structure.center_z, 0, local_z, roof_rotation)
                world_box_rotated({attic_x, attic_y, attic_z}, {attic_width, attic_height, .20}, roof_rotation, window)
                pane_z_local := local_z + f32(gable_end) * .115
                pane_x, pane_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    0,
                    pane_z_local,
                    roof_rotation,
                )
                world_box_rotated(
                    {pane_x, attic_y, pane_z},
                    {attic_width - frame_width * 1.35, attic_height - frame_width * 1.35, .045},
                    roof_rotation,
                    pane_color,
                )

                frame_z_local := local_z + f32(gable_end) * .145
                for side in -1 ..= 1 {
                    if side == 0 do continue
                    jamb_x, jamb_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        f32(side) * (attic_width * .5 + frame_width * .5),
                        frame_z_local,
                        roof_rotation,
                    )
                    world_box_rotated(
                        {jamb_x, attic_y, jamb_z},
                        {frame_width, attic_height + frame_width * 2, .11},
                        roof_rotation,
                        frame_color,
                    )
                    rail_x, rail_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        0,
                        frame_z_local,
                        roof_rotation,
                    )
                    world_box_rotated(
                        {rail_x, attic_y + f32(side) * (attic_height * .5 + frame_width * .5), rail_z},
                        {attic_width + frame_width * 2, frame_width, side < 0 ? f32(.18) : f32(.11)},
                        roof_rotation,
                        side < 0 ? formation_face_color(frame_color, math.PI, 0) : frame_color,
                    )
                }
                mullion_x, mullion_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    0,
                    frame_z_local + f32(gable_end) * .012,
                    roof_rotation,
                )
                world_box_rotated(
                    {mullion_x, attic_y, mullion_z},
                    {frame_width * .46, attic_height - frame_width * 1.2, .055},
                    roof_rotation,
                    mullion_color,
                )
                if attic_height >= 1.05 {
                    world_box_rotated(
                        {mullion_x, attic_y, mullion_z},
                        {attic_width - frame_width * 1.2, frame_width * .42, .055},
                        roof_rotation,
                        mullion_color,
                    )
                }
            }
        }
    }
}
