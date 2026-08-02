package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

world_architecture_window_detail :: proc(
    structure: terrain.Structure,
    face: architecture.Face,
    row, column: int,
    x, y, local_z, window_width, window_height: f32,
    window, shutter: canvas2d.Color,
    landmark, mixed_use, mixed_use_apartment_window, storefront_window: bool,
    facade_style: int,
) {
    identity := architecture.architecture_resolve_legacy_identity(structure)
    if !landmark {
        glass_x, glass_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            x,
            local_z + .125,
            structure.rotation,
        )
        glass_tone := int((structure.seed + u32(column * 17)) % 3)
        glass := canvas2d.Color{48, 72, 78, 255}
        if facade_style == 2 {
            if glass_tone == 0 {
                glass = {54, 94, 105, 255}
            } else if glass_tone == 1 {
                glass = {58, 99, 109, 255}
            } else {
                glass = {49, 87, 99, 255}
            }
        } else if glass_tone == 0 {
            glass = {54, 78, 82, 255}
        } else if glass_tone == 1 {
            glass = {60, 84, 86, 255}
        }
        if storefront_window do glass = {43, 77, 76, 255}
        reveal := formation_face_color(window, math.PI, 0)
        interior, interior_light := world_architecture_window_interior(
            structure,
            face,
            row,
            column,
            storefront_window || mixed_use_apartment_window,
        )
        if storefront_window || mixed_use_apartment_window {
            // A warm luminous surface behind the glazing keeps shops
            // occupied and legible after dark. Mullions, merchandise,
            // and the glass panel remain in front, so this reads as an
            // interior rather than a luminous exterior sign.
            backing_x, backing_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                x,
                local_z + .085,
                structure.rotation,
            )
            backing_color := interior
            if storefront_window {
                // Recess the shop visually behind its glazing. A bright
                // emissive plane nearly flush with the pane made the
                // full-glass bay read like a cream shutter in daylight.
                backing_color = color_lerp({46, 43, 39, 255}, interior, .30)
            } else if mixed_use_apartment_window {
                backing_color = color_lerp(interior, {43, 77, 76, 255}, .38)
            }
            if storefront_window {
                world_box_rotated(
                    {backing_x, y, backing_z},
                    {window_width * .90, window_height * .86, .025},
                    structure.rotation,
                    backing_color,
                )
            } else {
                world_box_rotated_material(
                    {backing_x, y, backing_z},
                    {window_width * .90, window_height * .86, .025},
                    structure.rotation,
                    backing_color,
                    .Emissive,
                )
            }
        } else {
            world_box_rotated(
                {glass_x, y, glass_z},
                {window_width * .94, window_height * .92, .045},
                structure.rotation,
                reveal,
            )
        }
        if interior_light > 0 {
            if storefront_window {
                glass = color_lerp({38, 73, 77, 255}, interior, .46)
                interior_light *= .90
            } else {
                glass = interior
            }
        }
        if storefront_window {
            world_glass_panel(
                {glass_x, y, glass_z},
                window_width * .84,
                window_height * .82,
                structure.rotation,
                glass,
                interior_light,
                world_architecture_window_room(structure, face, row, column),
            )
        } else {
            generated_surround :=
                facade_style == 2 ? canvas2d.Color{208, 207, 184, 255} : (identity.region == .Aegean ? canvas2d.Color{238, 233, 211, 255} : canvas2d.Color{190, 166, 128, 255})
            generated_iron := facade_style == 2 ? canvas2d.Color{58, 79, 81, 255} : canvas2d.Color{70, 65, 59, 255}
            generated_flower_box :=
                mixed_use ? mixed_use_apartment_window : window_has_flower_box(structure.seed, row, column)
            generated_balcony :=
                (mixed_use && row == 1) ||
                (facade_style == 1 && row > 0) ||
                (facade_style == 0 && row > 0 && row % 2 == 0)
            world_architecture_generated_window(
                structure,
                {glass_x, y, glass_z},
                structure.rotation,
                window_width * .84,
                window_height * .82,
                face,
                row,
                column,
                glass,
                generated_surround,
                shutter,
                generated_iron,
                interior_light,
                !generated_flower_box && !generated_balcony,
            )
        }
        if (structure.seed + u32(row * 11 + column)) % 4 == 0 {
            curtain := facade_style == 2 ? canvas2d.Color{205, 197, 170, 255} : canvas2d.Color{190, 169, 145, 255}
            for curtain_side in -1 ..= 1 {
                if curtain_side == 0 do continue
                curtain_x, curtain_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x + f32(curtain_side) * window_width * .31,
                    local_z + .095,
                    structure.rotation,
                )
                world_box_rotated(
                    {curtain_x, y, curtain_z},
                    {window_width * .10, window_height * .68, .025},
                    structure.rotation,
                    curtain,
                )
            }
        }
        mullion := facade_style == 2 ? canvas2d.Color{183, 192, 174, 255} : canvas2d.Color{177, 163, 137, 255}
        world_box_rotated({glass_x, y, glass_z}, {.065, window_height * .82, .055}, structure.rotation, mullion)
        if row == 0 && structure.height < 15 && structure.seed % 3 == 1 {
            for shop_division in -1 ..= 1 {
                if shop_division == 0 do continue
                division_x, division_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x + f32(shop_division) * window_width * .25,
                    local_z + .145,
                    structure.rotation,
                )
                world_box_rotated(
                    {division_x, y, division_z},
                    {.045, window_height * .82, .045},
                    structure.rotation,
                    mullion,
                )
            }
        }
        sill_x, sill_z := world_rotate_xz(structure.center_x, structure.center_z, x, local_z + .18, structure.rotation)
        sill := facade_style == 2 ? canvas2d.Color{166, 171, 151, 255} : canvas2d.Color{190, 166, 128, 255}
        world_box_rotated(
            {sill_x, y - window_height * .5 - .11, sill_z},
            {window_width + .38, .10, .30},
            structure.rotation,
            sill,
        )
        if storefront_window {
            // A curb-height kick panel protects the bottom of the
            // full-glass bay without overlapping the visible pane.
            // A narrow brass cap takes trolley and foot traffic.
            bulkhead_x, bulkhead_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                x,
                local_z + .17,
                structure.rotation,
            )
            world_box_rotated(
                {bulkhead_x, structure.base_y + .18, bulkhead_z},
                {window_width + .30, .34, .12},
                structure.rotation,
                facade_style == 2 ? canvas2d.Color{54, 83, 82, 255} : canvas2d.Color{91, 66, 54, 255},
            )
            bulkhead_cap_x, bulkhead_cap_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                x,
                local_z + .205,
                structure.rotation,
            )
            world_box_rotated(
                {bulkhead_cap_x, structure.base_y + .37, bulkhead_cap_z},
                {window_width + .20, .045, .055},
                structure.rotation,
                {180, 142, 74, 255},
            )
            transom_x, transom_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                x,
                local_z + .19,
                structure.rotation,
            )
            world_box_rotated(
                {transom_x, y + window_height * .27, transom_z},
                {window_width * .90, .075, .06},
                structure.rotation,
                mullion,
            )
            // A shallow rear display line breaks the luminous backing
            // into a believable room. Keep its stock sparse and below
            // eye level so the full-glass frontage still feels open.
            rear_shelf_z_local := local_z + .105
            rear_shelf_x, rear_shelf_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                x,
                rear_shelf_z_local,
                structure.rotation,
            )
            // Stagger the two bays so they read as one curated shop
            // display rather than mirrored procedural shelving.
            rear_shelf_y := structure.base_y + 1.50 + f32(column % 2) * .18
            rear_wood := facade_style == 2 ? canvas2d.Color{78, 93, 84, 255} : canvas2d.Color{103, 75, 55, 255}
            world_box_rotated(
                {rear_shelf_x, rear_shelf_y, rear_shelf_z},
                {window_width * .62, .075, .045},
                structure.rotation,
                rear_wood,
            )
            for support in -1 ..= 1 {
                if support == 0 do continue
                support_x, support_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x + f32(support) * window_width * .27,
                    rear_shelf_z_local,
                    structure.rotation,
                )
                world_box_rotated(
                    {support_x, rear_shelf_y - .31, support_z},
                    {.055, .62, .04},
                    structure.rotation,
                    formation_face_color(rear_wood, math.PI, 0),
                )
            }
            merchandise_kind := int((structure.seed >> 6) % 4)
            for rear_item in -1 ..= 1 {
                if rear_item == 0 do continue
                rear_item_local_x := x + f32(rear_item) * window_width * .18
                rear_item_x, rear_item_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    rear_item_local_x,
                    rear_shelf_z_local + .012,
                    structure.rotation,
                )
                switch merchandise_kind {
                case 0:
                    rear_color := rear_item < 0 ? canvas2d.Color{152, 94, 59, 255} : canvas2d.Color{86, 117, 111, 255}
                    world_tapered_box_rotated(
                        {rear_item_x, rear_shelf_y + .18, rear_item_z},
                        .34,
                        .16,
                        .07,
                        .23,
                        .08,
                        structure.rotation,
                        rear_color,
                    )
                case 1:
                    for produce in -1 ..= 1 {
                        produce_x, produce_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            rear_item_local_x + f32(produce) * .075,
                            rear_shelf_z_local + .012,
                            structure.rotation,
                        )
                        world_ellipsoid_rotated(
                            {produce_x, rear_shelf_y + .105 + f32(abs(produce)) * .018, produce_z},
                            .055,
                            .065,
                            .035,
                            structure.rotation,
                            produce == 0 ? canvas2d.Color{179, 83, 57, 255} : canvas2d.Color{177, 139, 65, 255},
                            .BRDF,
                        )
                    }
                case 2:
                    for folded in 0 ..< 2 {
                        world_box_rotated(
                            {rear_item_x, rear_shelf_y + .055 + f32(folded) * .075, rear_item_z},
                            {.29 - f32(folded) * .025, .065, .04},
                            structure.rotation,
                            folded == 0 ? canvas2d.Color{78, 117, 122, 255} : canvas2d.Color{170, 105, 82, 255},
                        )
                    }
                case:
                    for spine in -1 ..= 1 {
                        spine_x, spine_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            rear_item_local_x + f32(spine) * .06,
                            rear_shelf_z_local + .012,
                            structure.rotation,
                        )
                        world_box_rotated(
                            {spine_x, rear_shelf_y + .14, spine_z},
                            {.045, .28 + f32(spine + 1) * .025, .04},
                            structure.rotation,
                            spine < 0 ? canvas2d.Color{103, 67, 58, 255} : spine == 0 ? canvas2d.Color{69, 99, 100, 255} : canvas2d.Color{155, 116, 62, 255},
                        )
                    }
                }
            }
            shelf_x, shelf_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                x,
                local_z + .22,
                structure.rotation,
            )
            shelf_y := structure.base_y + .88
            world_box_rotated(
                {shelf_x, shelf_y, shelf_z},
                {window_width * .82, .075, .10},
                structure.rotation,
                {146, 105, 68, 255},
            )
            for display in -1 ..= 1 {
                focal_display := column % 2 == 0
                // One bay gets a single hero object; its neighbor gets
                // two smaller groups. This asymmetry is retained across
                // all business families while the merchandise itself
                // supplies the distinct silhouette.
                if focal_display && display != 0 do continue
                if !focal_display && display == 0 do continue
                display_local_x := x + f32(display) * window_width * .25
                display_x, display_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    display_local_x,
                    local_z + .24,
                    structure.rotation,
                )
                display_color :=
                    display < 0 ? canvas2d.Color{190, 126, 72, 255} : display > 0 ? canvas2d.Color{111, 142, 105, 255} : canvas2d.Color{202, 180, 119, 255}
                switch merchandise_kind {
                case 0:
                    // Tapered ceramic vessels with a contrasting lip.
                    vessel_height := display == 0 ? f32(.72) : f32(.42)
                    world_tapered_box_rotated(
                        {display_x, shelf_y + vessel_height * .5, display_z},
                        vessel_height,
                        display == 0 ? f32(.30) : f32(.20),
                        display == 0 ? f32(.12) : f32(.09),
                        display == 0 ? f32(.42) : f32(.29),
                        display == 0 ? f32(.15) : f32(.11),
                        structure.rotation,
                        display_color,
                    )
                    world_box_rotated(
                        {display_x, shelf_y + vessel_height + .015, display_z},
                        {display == 0 ? f32(.46) : f32(.32), .045, .12},
                        structure.rotation,
                        formation_face_color(display_color, .4, 0),
                    )
                case 1:
                    // Low produce crate with a small mound of fruit.
                    world_box_rotated(
                        {display_x, shelf_y + (display == 0 ? f32(.14) : f32(.105)), display_z},
                        {display == 0 ? f32(.70) : f32(.42), display == 0 ? f32(.28) : f32(.21), .10},
                        structure.rotation,
                        {151, 101, 62, 255},
                    )
                    fruit_extent := display == 0 ? 2 : 1
                    for fruit in -fruit_extent ..= fruit_extent {
                        fruit_x, fruit_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            display_local_x + f32(fruit) * .095,
                            local_z + .255,
                            structure.rotation,
                        )
                        fruit_color :=
                            fruit == 0 ? canvas2d.Color{203, 83, 57, 255} : fruit < 0 ? canvas2d.Color{218, 154, 60, 255} : canvas2d.Color{112, 151, 73, 255}
                        world_ellipsoid_rotated(
                            {
                                fruit_x,
                                shelf_y + (display == 0 ? f32(.34) : f32(.255)) + f32(abs(fruit)) * .018,
                                fruit_z,
                            },
                            .075,
                            .075,
                            .045,
                            structure.rotation,
                            fruit_color,
                            .BRDF,
                        )
                    }
                case 2:
                    // Folded coastal textiles in alternating dyed bands.
                    fold_count := display == 0 ? 5 : 3
                    for fold in 0 ..< fold_count {
                        fold_color :=
                            fold == 0 ? display_color : fold == 1 ? canvas2d.Color{218, 190, 139, 255} : canvas2d.Color{79, 119, 126, 255}
                        world_box_rotated(
                            {display_x, shelf_y + .065 + f32(fold) * .095, display_z},
                            {(display == 0 ? f32(.64) : f32(.40)) - f32(fold) * .035, .085, .10},
                            structure.rotation,
                            fold_color,
                        )
                    }
                case:
                    // A short run of upright books with uneven spines.
                    book_count := display == 0 ? 5 : 3
                    for book_index in 0 ..< book_count {
                        book := book_index - book_count / 2
                        book_x, book_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            display_local_x + f32(book) * .085,
                            local_z + .24,
                            structure.rotation,
                        )
                        book_color :=
                            book_index % 3 == 0 ? canvas2d.Color{119, 73, 61, 255} : book_index % 3 == 1 ? canvas2d.Color{71, 108, 111, 255} : canvas2d.Color{182, 139, 67, 255}
                        world_box_rotated(
                            {book_x, shelf_y + .18 + f32(book_index % 3) * .025, book_z},
                            {.070, .34 + f32(book_index % 3) * .05, .08},
                            structure.rotation,
                            book_color,
                        )
                    }
                }
            }
            for reflection in -1 ..= 1 {
                if reflection == 0 do continue
                reflection_x, reflection_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x + f32(reflection) * window_width * .28,
                    local_z + .255,
                    structure.rotation,
                )
                world_box_rotated(
                    {reflection_x, y + window_height * .06, reflection_z},
                    {.055, window_height * .44, .025},
                    structure.rotation,
                    {116, 151, 151, 255},
                )
            }
            pendant_x, pendant_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                x + (column % 2 == 0 ? -window_width * .18 : window_width * .18),
                local_z + .26,
                structure.rotation,
            )
            pendant_top := y + window_height * .34
            world_box_rotated(
                {pendant_x, pendant_top - .18, pendant_z},
                {.035, .36, .025},
                structure.rotation,
                {68, 65, 58, 255},
            )
            world_box_rotated_material(
                {pendant_x, pendant_top - .40, pendant_z},
                {.26, .18, .055},
                structure.rotation,
                {226, 179, 91, 255},
                .Emissive,
            )
        }
        if structure.height < 15 && structure.seed % 5 == 4 {
            apron_x, apron_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                x,
                local_z + .17,
                structure.rotation,
            )
            world_box_rotated(
                {apron_x, y - window_height * .34, apron_z},
                {window_width * .88, window_height * .24, .08},
                structure.rotation,
                facade_style == 2 ? canvas2d.Color{92, 119, 118, 255} : canvas2d.Color{142, 103, 75, 255},
            )
        }
        world_box_rotated(
            {glass_x, y + window_height * .08, glass_z},
            {window_width * .84, .055, .055},
            structure.rotation,
            mullion,
        )
    }
}
