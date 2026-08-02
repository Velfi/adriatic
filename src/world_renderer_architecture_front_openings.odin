package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

world_architecture_front_windows :: proc(
    structure: terrain.Structure,
    opening_layout: ^architecture.Opening_Layout,
    window, shutter: canvas2d.Color,
    rich_front, storefront_front, mixed_use, landmark: bool,
    facade_style: int,
) {
    if rich_front && opening_layout != nil {
        for opening in opening_layout.openings[:opening_layout.count] {
            if opening.face != .Front || opening.kind != .Window do continue
            row, column := opening.row, opening.column
            storefront_window := storefront_front && row == 0
            apartment_box_column := (structure.seed & 1) == 0 ? 1 : 0
            mixed_use_apartment_window := mixed_use && row == 1 && column == apartment_box_column
            x := opening.horizontal
            y := structure.base_y + opening.y
            window_width, window_height := opening.width, opening.height
            local_z := structure.depth * .5 + .16
            wx, wz := world_rotate_xz(structure.center_x, structure.center_z, x, local_z, structure.rotation)
            world_box_rotated({wx, y, wz}, {window_width, window_height, .22}, structure.rotation, window)
            if landmark {
                glass_x, glass_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x,
                    local_z + .125,
                    structure.rotation,
                )
                glass, interior_light := world_architecture_window_interior(
                    structure,
                    opening.face,
                    row,
                    column,
                    storefront_window || mixed_use_apartment_window,
                )
                world_glass_panel(
                    {glass_x, y, glass_z},
                    window_width * .84,
                    window_height * .82,
                    structure.rotation,
                    glass,
                    interior_light,
                    world_architecture_window_room(structure, opening.face, row, column),
                )
            }
            world_architecture_window_detail(
                structure,
                opening.face,
                row,
                column,
                x,
                y,
                local_z,
                window_width,
                window_height,
                window,
                shutter,
                landmark,
                mixed_use,
                mixed_use_apartment_window,
                storefront_window,
                facade_style,
            )
            if !landmark && (facade_style == 0 || facade_style == 1) {
                trim := facade_style == 1 ? canvas2d.Color{205, 190, 157, 255} : canvas2d.Color{190, 166, 128, 255}
                trim_width := window_width + .40
                trim_z := local_z + .045
                trim_x, trim_world_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x,
                    trim_z,
                    structure.rotation,
                )
                world_box_rotated(
                    {trim_x, y + window_height * .5 + .12, trim_world_z},
                    {trim_width, .075, .16},
                    structure.rotation,
                    trim,
                )
                world_box_rotated(
                    {trim_x, y - window_height * .5 - .10, trim_world_z},
                    {trim_width * .92, .065, .18},
                    structure.rotation,
                    formation_face_color(trim, math.PI, 0),
                )
            }
            mixed_use_apartment_box := mixed_use_apartment_window
            show_flower_box := mixed_use ? mixed_use_apartment_box : window_has_flower_box(structure.seed, row, column)
            has_juliet_guard := show_flower_box && row > 0
            if !landmark && !storefront_window && show_flower_box {
                flower_x, flower_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x,
                    local_z + .30,
                    structure.rotation,
                )
                world_box_rotated(
                    {flower_x, y - window_height * .5 - .18, flower_z},
                    {window_width + .56, .12, .22},
                    structure.rotation,
                    {178, 111, 73, 255},
                )
                world_window_flower_bunch_billboard(
                    structure,
                    x,
                    y - window_height * .5 - .10,
                    local_z + .35,
                    window_width,
                    row,
                    column,
                )
                // Flower-box openings still need a small Juliet guard. Without
                // it the planter lip reads as an unsupported balcony with its
                // upper railing missing.
                guard_width := window_width + .48
                guard_z := local_z + .40
                guard_color := facade_style == 2 ? canvas2d.Color{64, 82, 83, 255} : canvas2d.Color{83, 68, 62, 255}
                guard_height: f32 = .09
                guard_center_above_sill: f32 = 1.04
                post_width: f32 = .055
                planter_center_below_sill: f32 = .18
                planter_height: f32 = .12
                post_base_above_sill := -planter_center_below_sill + planter_height * .5
                post_top_above_sill := guard_center_above_sill - guard_height * .5
                post_height := post_top_above_sill - post_base_above_sill
                post_center_above_sill := (post_base_above_sill + post_top_above_sill) * .5
                post_center_span := guard_width - post_width
                guard_x, guard_world_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x,
                    guard_z,
                    structure.rotation,
                )
                if has_juliet_guard {
                    world_box_rotated(
                        {guard_x, y - window_height * .5 + guard_center_above_sill, guard_world_z},
                        {guard_width, guard_height, .08},
                        structure.rotation,
                        guard_color,
                    )
                    for post in -2 ..= 2 {
                        post_x, post_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x + f32(post) * post_center_span * .25,
                            guard_z,
                            structure.rotation,
                        )
                        world_box_rotated(
                            {post_x, y - window_height * .5 + post_center_above_sill, post_z},
                            {post_width, post_height, .07},
                            structure.rotation,
                            guard_color,
                        )
                    }
                }
            }
            if !landmark && !storefront_window {
                if mixed_use && row == 1 {
                    // The first residential level belongs to a pair of
                    // dwellings reached from the side stair doors. One unit
                    // receives the planted Juliet guard above; give its
                    // companion a quieter iron rail instead of handing it to
                    // an unrelated generic façade style.
                    if !mixed_use_apartment_window {
                        companion_width := window_width + .42
                        companion_z := local_z + .37
                        companion_color :=
                            facade_style == 2 ? canvas2d.Color{64, 82, 83, 255} : canvas2d.Color{83, 68, 62, 255}
                        companion_x, companion_world_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x,
                            companion_z,
                            structure.rotation,
                        )
                        sill_y := y - window_height * .5
                        companion_slab_center_y := sill_y - .11
                        companion_slab_height: f32 = .12
                        companion_slab_top_y := companion_slab_center_y + companion_slab_height * .5
                        world_box_rotated(
                            {companion_x, companion_slab_center_y, companion_world_z},
                            {companion_width + .12, companion_slab_height, .28},
                            structure.rotation,
                            {190, 158, 112, 255},
                        )
                        world_box_rotated(
                            {companion_x, sill_y + .92, companion_world_z},
                            {companion_width, .09, .075},
                            structure.rotation,
                            companion_color,
                        )
                        for companion_post in -2 ..= 2 {
                            companion_post_top_y := sill_y + .92 - .09 * .5
                            companion_post_height := companion_post_top_y - companion_slab_top_y
                            post_x, post_z := world_rotate_xz(
                                structure.center_x,
                                structure.center_z,
                                x + f32(companion_post) * companion_width * .24,
                                companion_z,
                                structure.rotation,
                            )
                            world_box_rotated(
                                {post_x, (companion_slab_top_y + companion_post_top_y) * .5, post_z},
                                {.055, companion_post_height, .07},
                                structure.rotation,
                                companion_color,
                            )
                        }
                    }
                } else if facade_style == 1 && row > 0 {
                    world_architecture_balcony(structure, x, local_z, y - window_height * .5, window_width, false)
                } else if facade_style == 2 {
                    // Blue façades use small fabric awnings rather than
                    // balconies, giving this seed variant a distinct profile.
                    awning_x, awning_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        x,
                        local_z + .12,
                        structure.rotation,
                    )
                    world_box_rotated(
                        {awning_x, y + window_height * .5 + .30, awning_z},
                        {window_width + .65, .12, .34},
                        structure.rotation,
                        shutter,
                    )
                } else {
                    if facade_style == 0 && row > 0 && row % 2 == 0 {
                        world_architecture_balcony(structure, x, local_z, y - window_height * .5, window_width, true)
                        planter_x, planter_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x,
                            local_z + .34,
                            structure.rotation,
                        )
                        world_box_rotated(
                            {planter_x, y - window_height * .5 + .10, planter_z},
                            {window_width + .25, .12, .12},
                            structure.rotation,
                            {107, 132, 92, 255},
                        )
                    } else if !has_juliet_guard && storefront_window {
                        shutter_width := clamp(window_width * .30, f32(.42), f32(.62))
                        for side in -1 ..= 1 {
                            if side == 0 do continue
                            sx, sz := world_rotate_xz(
                                wx,
                                wz,
                                f32(side) * (window_width * .5 + shutter_width * .5 + .08),
                                0,
                                structure.rotation,
                            )
                            world_box_rotated(
                                {sx, y, sz},
                                {shutter_width, window_height + .24, .28},
                                structure.rotation,
                                shutter,
                            )
                            hinge_x, hinge_z := world_rotate_xz(sx, sz, 0, .17, structure.rotation)
                            for hinge in -1 ..= 1 {
                                if hinge == 0 do continue
                                world_box_rotated(
                                    {hinge_x, y + f32(hinge) * window_height * .28, hinge_z},
                                    {shutter_width * .72, .055, .06},
                                    structure.rotation,
                                    {70, 65, 59, 255},
                                )
                            }
                            holdback_x, holdback_z := world_rotate_xz(
                                sx,
                                sz,
                                f32(side) * shutter_width * .34,
                                .19,
                                structure.rotation,
                            )
                            world_box_rotated(
                                {holdback_x, y - window_height * .58, holdback_z},
                                {.10, .18, .07},
                                structure.rotation,
                                {70, 65, 59, 255},
                            )
                            if row == 0 && structure.seed % 5 == 0 {
                                world_box_rotated(
                                    {hinge_x, y, hinge_z},
                                    {shutter_width + .04, .12, .07},
                                    structure.rotation,
                                    {203, 174, 119, 255},
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
