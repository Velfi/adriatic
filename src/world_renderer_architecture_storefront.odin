package main

import buildings "../packages/buildings"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

world_architecture_storefront :: proc(
    structure: terrain.Structure,
    identity: buildings.Identity,
    door_width, door_height, step_height: f32,
) {
    storefront := identity.archetype == .Shop_House || identity.archetype == .Mixed_Use_Dwelling
    if storefront || (structure.height < 52 && structure.seed % 2 == 0) {
        awning_x, awning_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .46,
            structure.rotation,
        )
        // Shop canvas comes from a small sun-faded coastal palette. Keep
        // two colors per awning so stripes, checks, and the loose fringe
        // read as dyed cloth rather than extra pieces of architecture.
        awning_color, stripe_color := canvas2d.Color{}, canvas2d.Color{}
        switch structure.seed % 6 {
        case 0:
            awning_color, stripe_color = {177, 73, 58, 255}, {231, 203, 157, 255}
        case 1:
            awning_color, stripe_color = {48, 112, 120, 255}, {224, 202, 157, 255}
        case 2:
            awning_color, stripe_color = {205, 145, 55, 255}, {105, 67, 73, 255}
        case 3:
            awning_color, stripe_color = {83, 111, 74, 255}, {226, 194, 145, 255}
        case 4:
            awning_color, stripe_color = {101, 78, 119, 255}, {220, 174, 130, 255}
        case:
            awning_color, stripe_color = {196, 105, 71, 255}, {76, 111, 130, 255}
        }
        storefront_business_kind := int((structure.seed >> 6) % 4)
        if identity.archetype == .Mixed_Use_Dwelling {
            // Tie the canvas to the actual tenant family so neighboring
            // mixed-use buildings read as different businesses, not the
            // same storefront with shuffled merchandise.
            switch storefront_business_kind {
            case 0:
                // pottery
                awning_color, stripe_color = {165, 79, 55, 255}, {232, 203, 157, 255}
            case 1:
                // produce
                awning_color, stripe_color = {72, 108, 67, 255}, {221, 198, 142, 255}
            case 2:
                // textiles
                awning_color, stripe_color = {72, 78, 126, 255}, {202, 151, 83, 255}
            case:
                // books
                awning_color, stripe_color = {112, 57, 61, 255}, {218, 190, 151, 255}
            }
        }
        awning_width := storefront ? max(door_width + 1.4, structure.width - 2.4) : door_width + 1.4
        pattern_kind := int((structure.seed >> 3) % 4)
        if storefront {
            // A real projecting fabric canopy: its rear edge is fixed high
            // on the wall, then four broad planes bow gently toward the
            // lower front rail. Coloring the planes directly keeps the
            // existing painted-surface language without stacking decals
            // over a horizontal architectural slab.
            panel_count := pattern_kind == 2 ? 9 : 7
            panel_width := awning_width / f32(panel_count)
            canopy_z: [5]f32 = {
                structure.depth * .5 + .06,
                structure.depth * .5 + .40,
                structure.depth * .5 + .87,
                structure.depth * .5 + 1.38,
                structure.depth * .5 + 1.82,
            }
            canopy_y: [5]f32 = {
                structure.base_y + step_height + door_height + 1.36,
                structure.base_y + step_height + door_height + 1.31,
                structure.base_y + step_height + door_height + 1.16,
                structure.base_y + step_height + door_height + .88,
                structure.base_y + step_height + door_height + .64,
            }
            for panel in 0 ..< panel_count {
                local_x_0 := -awning_width * .5 + panel_width * f32(panel)
                local_x_1 := local_x_0 + panel_width + .012
                for band in 0 ..< 4 {
                    painted :=
                        pattern_kind == 0 ? panel % 2 == 0 : pattern_kind == 1 ? panel % 3 == 1 : pattern_kind == 2 ? (panel + band + int(structure.seed >> 7)) % 2 == 0 : panel == panel_count / 2 || band == 2
                    fabric_color := painted ? stripe_color : awning_color
                    x_00, z_00 := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        local_x_0,
                        canopy_z[band],
                        structure.rotation,
                    )
                    x_10, z_10 := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        local_x_1,
                        canopy_z[band],
                        structure.rotation,
                    )
                    x_11, z_11 := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        local_x_1,
                        canopy_z[band + 1],
                        structure.rotation,
                    )
                    x_01, z_01 := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        local_x_0,
                        canopy_z[band + 1],
                        structure.rotation,
                    )
                    world_quad(
                        {x_00, canopy_y[band], z_00},
                        {x_01, canopy_y[band + 1], z_01},
                        {x_11, canopy_y[band + 1], z_11},
                        {x_10, canopy_y[band], z_10},
                        fabric_color,
                    )
                }
            }
            rail_x, rail_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + 1.82,
                structure.rotation,
            )
            world_metal_box_rotated(
                {rail_x, canopy_y[4], rail_z},
                {awning_width + .16, .11, .11},
                structure.rotation,
                {74, 67, 58, 255},
            )
        } else {
            world_box_rotated(
                {awning_x, structure.base_y + step_height + door_height + .82, awning_z},
                {awning_width, .14, .52},
                structure.rotation,
                awning_color,
            )
            for stripe in -1 ..= 1 {
                stripe_x, stripe_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    f32(stripe) * awning_width * .30,
                    structure.depth * .5 + .49,
                    structure.rotation,
                )
                world_box_rotated(
                    {stripe_x, structure.base_y + step_height + door_height + .832, stripe_z},
                    {awning_width * .28, .035, .54},
                    structure.rotation,
                    stripe % 2 == 0 ? stripe_color : awning_color,
                )
            }
        }
        if storefront {
            valance_segments := 11
            segment_width := awning_width / f32(valance_segments)
            for segment in 0 ..< valance_segments {
                segment_local_x := -awning_width * .5 + segment_width * (f32(segment) + .5)
                segment_x, segment_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    segment_local_x,
                    structure.depth * .5 + 1.83,
                    structure.rotation,
                )
                fringe_long := (segment + int(structure.seed >> 5)) % 3 == 0
                fringe_height := fringe_long ? f32(.40) : f32(.30)
                fringe_color :=
                    pattern_kind == 3 ? (segment % 3 == 1 ? stripe_color : awning_color) : (segment + pattern_kind) % 2 == 0 ? stripe_color : awning_color
                fringe_bottom_y := structure.base_y + step_height + door_height + .64 - fringe_height
                world_box_rotated(
                    {segment_x, structure.base_y + step_height + door_height + .64 - fringe_height * .5, segment_z},
                    {segment_width * .78, fringe_height, .075},
                    structure.rotation,
                    fringe_color,
                )
                // Every third drop finishes in a shallow weighted point.
                // The alternating hem breaks the former row of rectangular
                // blocks into a fabric silhouette while exposing more
                // glass beneath the canopy.
                if fringe_long {
                    tail_left_x, tail_left_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        segment_local_x - segment_width * .27,
                        structure.depth * .5 + 1.875,
                        structure.rotation,
                    )
                    tail_right_x, tail_right_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        segment_local_x + segment_width * .27,
                        structure.depth * .5 + 1.875,
                        structure.rotation,
                    )
                    tail_tip_x, tail_tip_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        segment_local_x,
                        structure.depth * .5 + 1.885,
                        structure.rotation,
                    )
                    tail_color := formation_face_color(fringe_color, math.PI, 1)
                    tail_left := third_person.Vec3{tail_left_x, fringe_bottom_y + .015, tail_left_z}
                    tail_right := third_person.Vec3{tail_right_x, fringe_bottom_y + .015, tail_right_z}
                    tail_tip := third_person.Vec3{tail_tip_x, fringe_bottom_y - .13, tail_tip_z}
                    world_triangle(tail_left, tail_tip, tail_right, tail_color)
                    world_triangle(tail_right, tail_tip, tail_left, tail_color)
                }
            }
            // Three small downlights tuck behind the valance. Their warm
            // lenses give the canopy a pedestrian-scale night rhythm
            // while the display windows remain the dominant light source.
            for fixture in -1 ..= 1 {
                fixture_local_x := f32(fixture) * awning_width * .31
                fixture_x, fixture_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    fixture_local_x,
                    structure.depth * .5 + 1.47,
                    structure.rotation,
                )
                fixture_y := structure.base_y + step_height + door_height + .48
                world_box_rotated(
                    {fixture_x, fixture_y, fixture_z},
                    {.28, .10, .22},
                    structure.rotation,
                    {65, 60, 53, 255},
                )
                lens_x, lens_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    fixture_local_x,
                    structure.depth * .5 + 1.59,
                    structure.rotation,
                )
                world_box_rotated_material(
                    {lens_x, fixture_y - .025, lens_z},
                    {.16, .055, .035},
                    structure.rotation,
                    {255, 183, 88, 255},
                    .Emissive,
                )
            }
        } else {
            fascia_x, fascia_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .73,
                structure.rotation,
            )
            world_box_rotated(
                {fascia_x, structure.base_y + step_height + door_height + .74, fascia_z},
                {awning_width, .12, .09},
                structure.rotation,
                formation_face_color(awning_color, math.PI, 0),
            )
        }
        for support_side in -1 ..= 1 {
            if support_side == 0 do continue
            support_local_x := f32(support_side) * awning_width * .42
            if storefront {
                // Triangular side arms make the canopy visibly wall hung
                // instead of supported by posts or floating over the shop.
                arm_rear_z := structure.depth * .5 + .12
                arm_front_z := structure.depth * .5 + 1.76
                arm_rear_y := structure.base_y + step_height + door_height + 1.20
                arm_front_y := structure.base_y + step_height + door_height + .52
                arm_x_0, arm_z_0 := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    support_local_x - .035,
                    arm_rear_z,
                    structure.rotation,
                )
                arm_x_1, arm_z_1 := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    support_local_x - .035,
                    arm_front_z,
                    structure.rotation,
                )
                arm_x_2, arm_z_2 := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    support_local_x + .035,
                    arm_front_z,
                    structure.rotation,
                )
                arm_x_3, arm_z_3 := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    support_local_x + .035,
                    arm_rear_z,
                    structure.rotation,
                )
                world_quad(
                    {arm_x_0, arm_rear_y + .035, arm_z_0},
                    {arm_x_1, arm_front_y + .035, arm_z_1},
                    {arm_x_2, arm_front_y - .035, arm_z_2},
                    {arm_x_3, arm_rear_y - .035, arm_z_3},
                    {77, 69, 60, 255},
                )
                awning_bracket_x, awning_bracket_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    support_local_x,
                    structure.depth * .5 + .10,
                    structure.rotation,
                )
                world_metal_box_rotated(
                    {awning_bracket_x, arm_rear_y - .23, awning_bracket_z},
                    {.10, .58, .10},
                    structure.rotation,
                    {77, 69, 60, 255},
                )
            } else {
                support_x, support_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    support_local_x,
                    structure.depth * .5 + .39,
                    structure.rotation,
                )
                world_box_rotated(
                    {support_x, structure.base_y + step_height + door_height + .40, support_z},
                    {.07, .74, .08},
                    structure.rotation,
                    {77, 69, 60, 255},
                )
            }
        }
        commercial :=
            identity.archetype == .Shop_House ||
            identity.archetype == .Mixed_Use_Dwelling ||
            identity.archetype == .Workshop ||
            identity.archetype == .Harbor_Office ||
            identity.archetype == .Market_Hall ||
            identity.archetype == .Post_Office
        // Named storefronts receive their commissioned sign in
        // world_business_sign_for_resident, where story ownership is
        // available. Do not put a random clinic, post office, or bakery
        // identity on an unrelated procedural storefront here.
        if commercial && !storefront && structure.height < 18 && structure.seed % 4 == 0 {
            sign_side := (structure.seed & 64) == 0 ? f32(-1) : f32(1)
            sign_local_x := storefront ? f32(0) : sign_side * (door_width * .5 + .72)
            // Storefront signs sit on the wall above the canopy head.
            // Keeping their lower edge clear of the rear fabric mount
            // prevents the enlarged awning from hiding the shop identity.
            sign_y := structure.base_y + step_height + door_height + (storefront ? f32(2.02) : f32(1.18))
            sign_depth := storefront ? f32(.24) : f32(.49)
            sign_x, sign_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                sign_local_x,
                structure.depth * .5 + sign_depth,
                structure.rotation,
            )
            sign_width := storefront ? min(awning_width * .38, f32(5.2)) : f32(1.15)
            sign_frame := canvas2d.Color{91, 119, 117, 255}
            if storefront {
                if identity.archetype == .Mixed_Use_Dwelling {
                    switch storefront_business_kind {
                    case 0:
                        sign_frame = {103, 65, 50, 255}
                    case 1:
                        sign_frame = {57, 80, 58, 255}
                    case 2:
                        sign_frame = {54, 59, 91, 255}
                    case:
                        sign_frame = {76, 43, 47, 255}
                    }
                } else {
                    sign_frame =
                        structure.seed % 3 == 0 ? canvas2d.Color{108, 75, 58, 255} : structure.seed % 3 == 1 ? canvas2d.Color{63, 88, 87, 255} : canvas2d.Color{113, 69, 64, 255}
                }
            }
            sign_height := storefront ? f32(.90) : f32(.54)
            world_box_rotated({sign_x, sign_y, sign_z}, {sign_width, sign_height, .10}, structure.rotation, sign_frame)
            if storefront {
                inset_x, inset_z := world_rotate_xz(sign_x, sign_z, 0, .065, structure.rotation)
                sign_inset := canvas2d.Color{61, 89, 85, 255}
                if identity.archetype == .Mixed_Use_Dwelling {
                    switch storefront_business_kind {
                    case 0:
                        sign_inset = {177, 92, 61, 255}
                    case 1:
                        sign_inset = {97, 124, 72, 255}
                    case 2:
                        sign_inset = {84, 88, 139, 255}
                    case:
                        sign_inset = {131, 64, 68, 255}
                    }
                } else {
                    sign_inset =
                        structure.seed % 3 == 0 ? canvas2d.Color{61, 89, 85, 255} : structure.seed % 3 == 1 ? canvas2d.Color{171, 91, 65, 255} : canvas2d.Color{193, 148, 72, 255}
                }
                world_box_rotated(
                    {inset_x, sign_y, inset_z},
                    {sign_width - .22, .66, .04},
                    structure.rotation,
                    sign_inset,
                )
                business_kind := storefront_business_kind
                glyph_color := canvas2d.Color{220, 185, 112, 255}
                switch business_kind {
                case 0:
                    // Three large vessel silhouettes: a tall amphora-like
                    // center flanked by shorter shop pottery.
                    for vessel in -1 ..= 1 {
                        vessel_x, vessel_z := world_rotate_xz(
                            sign_x,
                            sign_z,
                            f32(vessel) * .58,
                            .095,
                            structure.rotation,
                        )
                        vessel_height := vessel == 0 ? f32(.42) : f32(.30)
                        vessel_width := vessel == 0 ? f32(.29) : f32(.23)
                        world_box_rotated_material(
                            {vessel_x, sign_y - .015, vessel_z},
                            {vessel_width, vessel_height, .035},
                            structure.rotation,
                            glyph_color,
                            .Emissive,
                        )
                        world_box_rotated_material(
                            {vessel_x, sign_y + vessel_height * .48, vessel_z + .002},
                            {vessel_width + .11, .055, .038},
                            structure.rotation,
                            glyph_color,
                            .Emissive,
                        )
                    }
                case 1:
                    // A clustered market-produce emblem, broad enough to
                    // read as a group instead of the former dotted line.
                    produce_offsets := [5][2]f32 {
                        {-0.43, -0.075},
                        {0, -0.075},
                        {0.43, -0.075},
                        {-0.215, 0.145},
                        {0.215, 0.145},
                    }
                    for offset in produce_offsets {
                        produce_x, produce_z := world_rotate_xz(sign_x, sign_z, offset[0], .095, structure.rotation)
                        world_box_rotated_material(
                            {produce_x, sign_y + offset[1], produce_z},
                            {.22, .20, .035},
                            structure.rotation,
                            glyph_color,
                            .Emissive,
                        )
                    }
                case 2:
                    // Three folded textile bands form one unmistakable
                    // horizontal motif.
                    for band in -1 ..= 1 {
                        band_x, band_z := world_rotate_xz(sign_x, sign_z, f32(band) * .06, .095, structure.rotation)
                        world_box_rotated_material(
                            {band_x, sign_y + f32(band) * .105, band_z},
                            {1.14 - f32(abs(band)) * .17, .085, .035},
                            structure.rotation,
                            glyph_color,
                            .Emissive,
                        )
                    }
                case:
                    // A compact row of uneven upright book spines.
                    for spine in -2 ..= 2 {
                        spine_x, spine_z := world_rotate_xz(sign_x, sign_z, f32(spine) * .24, .095, structure.rotation)
                        spine_height := .30 + f32((spine + 2) % 3) * .065
                        world_box_rotated_material(
                            {spine_x, sign_y - .02 + spine_height * .08, spine_z},
                            {.12 + f32(abs(spine % 2)) * .03, spine_height, .035},
                            structure.rotation,
                            glyph_color,
                            .Emissive,
                        )
                    }
                }
            }
            sign_bracket_x, sign_bracket_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                sign_local_x,
                structure.depth * .5 + (storefront ? f32(.16) : f32(.29)),
                structure.rotation,
            )
            world_box_rotated(
                {sign_bracket_x, sign_y + sign_height * .5 + .08, sign_bracket_z},
                {storefront ? sign_width + .28 : f32(1.32), .07, .09},
                structure.rotation,
                {67, 61, 55, 255},
            )
            if identity.archetype == .Mixed_Use_Dwelling {
                // A projecting blade sign gives the shop an identity from
                // along the pavement. Put it opposite the seeded climbing
                // plant so the two vertical accents never compete.
                plant_side := (structure.seed & 1) == 0 ? f32(-1) : f32(1)
                blade_side := -plant_side
                blade_local_x := blade_side * structure.width * .39
                blade_center_z := structure.depth * .5 + .82
                blade_x, blade_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    blade_local_x,
                    blade_center_z,
                    structure.rotation,
                )
                blade_y := structure.base_y + step_height + door_height + 2.12
                world_box_rotated({blade_x, blade_y, blade_z}, {.13, .92, 1.05}, structure.rotation, sign_frame)
                blade_inset :=
                    structure.seed % 3 == 0 ? canvas2d.Color{61, 89, 85, 255} : structure.seed % 3 == 1 ? canvas2d.Color{171, 91, 65, 255} : canvas2d.Color{193, 148, 72, 255}
                blade_business_kind := int((structure.seed >> 6) % 4)
                blade_glyph := canvas2d.Color{227, 190, 111, 255}
                for face_side in -1 ..= 1 {
                    if face_side == 0 do continue
                    face_f := f32(face_side)
                    blade_inset_x, blade_inset_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        blade_local_x + face_f * .075,
                        blade_center_z,
                        structure.rotation,
                    )
                    world_box_rotated(
                        {blade_inset_x, blade_y, blade_inset_z},
                        {.035, .68, .76},
                        structure.rotation,
                        blade_inset,
                    )
                    glyph_face_x := blade_local_x + face_f * .098
                    switch blade_business_kind {
                    case 0:
                        vessel_x, vessel_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            glyph_face_x,
                            blade_center_z,
                            structure.rotation,
                        )
                        world_box_rotated_material(
                            {vessel_x, blade_y - .015, vessel_z},
                            {.025, .31, .23},
                            structure.rotation,
                            blade_glyph,
                            .Emissive,
                        )
                        world_box_rotated_material(
                            {vessel_x, blade_y + .15, vessel_z},
                            {.028, .045, .32},
                            structure.rotation,
                            blade_glyph,
                            .Emissive,
                        )
                    case 1:
                        produce_offsets := [5][2]f32 {
                            {-0.20, -0.08},
                            {0, -0.08},
                            {0.20, -0.08},
                            {-0.10, 0.10},
                            {0.10, 0.10},
                        }
                        for offset in produce_offsets {
                            produce_x, produce_z := world_rotate_xz(
                                structure.center_x,
                                structure.center_z,
                                glyph_face_x,
                                blade_center_z + offset[0],
                                structure.rotation,
                            )
                            world_box_rotated_material(
                                {produce_x, blade_y + offset[1], produce_z},
                                {.025, .13, .13},
                                structure.rotation,
                                blade_glyph,
                                .Emissive,
                            )
                        }
                    case 2:
                        for band in -1 ..= 1 {
                            band_x, band_z := world_rotate_xz(
                                structure.center_x,
                                structure.center_z,
                                glyph_face_x,
                                blade_center_z + f32(band) * .025,
                                structure.rotation,
                            )
                            world_box_rotated_material(
                                {band_x, blade_y + f32(band) * .105, band_z},
                                {.025, .055, .48 - f32(abs(band)) * .08},
                                structure.rotation,
                                blade_glyph,
                                .Emissive,
                            )
                        }
                    case:
                        for spine in -2 ..= 2 {
                            spine_x, spine_z := world_rotate_xz(
                                structure.center_x,
                                structure.center_z,
                                glyph_face_x,
                                blade_center_z + f32(spine) * .11,
                                structure.rotation,
                            )
                            spine_height := .20 + f32((spine + 2) % 3) * .045
                            world_box_rotated_material(
                                {spine_x, blade_y - .02 + spine_height * .08, spine_z},
                                {.025, spine_height, .07 + f32(abs(spine % 2)) * .02},
                                structure.rotation,
                                blade_glyph,
                                .Emissive,
                            )
                        }
                    }
                }
                blade_bracket_x, blade_bracket_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    blade_local_x,
                    structure.depth * .5 + .34,
                    structure.rotation,
                )
                blade_plate_x, blade_plate_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    blade_local_x,
                    structure.depth * .5 + .205,
                    structure.rotation,
                )
                world_box_rotated(
                    {blade_plate_x, blade_y + .54, blade_plate_z},
                    {.30, .34, .075},
                    structure.rotation,
                    {76, 68, 59, 255},
                )
                for bolt in -1 ..= 1 {
                    if bolt == 0 do continue
                    bolt_x, bolt_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        blade_local_x + f32(bolt) * .075,
                        structure.depth * .5 + .25,
                        structure.rotation,
                    )
                    world_box_rotated(
                        {bolt_x, blade_y + .54, bolt_z},
                        {.035, .035, .025},
                        structure.rotation,
                        {190, 154, 84, 255},
                    )
                }
                world_box_rotated(
                    {blade_bracket_x, blade_y + .54, blade_bracket_z},
                    {.10, .10, 1.10},
                    structure.rotation,
                    {67, 61, 55, 255},
                )
            }
        }
    }
}
