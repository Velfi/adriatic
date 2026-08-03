package main

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import terrain "../packages/terrain"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

world_architecture_entrance :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    opening_layout: ^architecture.Opening_Layout,
    identity: buildings.Identity,
    stone: canvas2d.Color,
    has_entrance, habitable, mixed_use: bool,
    facade_style: int,
) {
    if has_entrance && habitable {
        door_x, door_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .18,
            structure.rotation,
        )
        door :=
            facade_style == 2 ? canvas2d.Color{54, 91, 99, 255} : facade_style == 3 ? canvas2d.Color{109, 75, 57, 255} : canvas2d.Color{92, 66, 57, 255}
        if (structure.seed >> 11) & 3 == 1 {
            door = {72, 104, 101, 255}
        } else if (structure.seed >> 11) & 3 == 2 {
            door = {119, 71, 55, 255}
        }
        if mixed_use do door = {43, 77, 76, 255}
        door_width := clamp(structure.width * .13, f32(1.8), f32(2.8))
        door_height := clamp(structure.height * .075, f32(3.0), f32(4.0))
        step_height: f32 = .20
        door_center_local_y := step_height + door_height * .5
        if opening, found := architecture.opening_layout_find(opening_layout, .Front, .Door, 0, 0); found {
            door_width, door_height, door_center_local_y = opening.width, opening.height, opening.y
        }
        door_center_y := structure.base_y + door_center_local_y
        world_box_rotated({door_x, door_center_y, door_z}, {door_width, door_height, .24}, structure.rotation, door)
        panel_color := mixed_use ? canvas2d.Color{58, 99, 96, 255} : formation_face_color(door, math.PI, 0)
        world_architecture_mixed_use_glass_door(
            structure,
            mixed_use,
            door,
            panel_color,
            door_width,
            door_height,
            door_center_y,
            step_height,
        )
        if structure.height < 15 && structure.seed % 5 == 1 {
            divider_x, divider_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .355,
                structure.rotation,
            )
            world_box_rotated(
                {divider_x, door_center_y, divider_z},
                {.08, door_height * .88, .07},
                structure.rotation,
                {183, 157, 119, 255},
            )
        }
        if structure.height < 14 && structure.seed % 5 == 2 {
            for loading_slat in 0 ..< 3 {
                slat_x, slat_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    0,
                    structure.depth * .5 + .355,
                    structure.rotation,
                )
                world_box_rotated(
                    {slat_x, structure.base_y + step_height + door_height * (.25 + f32(loading_slat) * .25), slat_z},
                    {door_width * .82, .07, .07},
                    structure.rotation,
                    {70, 63, 55, 255},
                )
            }
        }
        handle_x, handle_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            door_width * .28,
            structure.depth * .5 + .365,
            structure.rotation,
        )
        world_metal_box_rotated(
            {handle_x, structure.base_y + step_height + door_height * .50, handle_z},
            {.11, .11, .10},
            structure.rotation,
            {196, 157, 79, 255},
        )
        kick_x, kick_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .37,
            structure.rotation,
        )
        world_box_rotated(
            {kick_x, structure.base_y + step_height + .24, kick_z},
            {door_width * .62, .18, .06},
            structure.rotation,
            {157, 124, 69, 255},
        )
        escutcheon_x, escutcheon_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            door_width * .28,
            structure.depth * .5 + .425,
            structure.rotation,
        )
        world_box_rotated(
            {escutcheon_x, structure.base_y + step_height + door_height * .40, escutcheon_z},
            {.07, .14, .035},
            structure.rotation,
            {174, 139, 76, 255},
        )
        if structure.seed % 3 == 0 {
            transom_x, transom_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .37,
                structure.rotation,
            )
            transom_y := structure.base_y + step_height + door_height - .28
            world_box_rotated(
                {transom_x, transom_y, transom_z},
                {door_width * .66, .38, .06},
                structure.rotation,
                {60, 87, 91, 255},
            )
            world_box_rotated(
                {transom_x, transom_y, transom_z},
                {.055, .38, .075},
                structure.rotation,
                {190, 171, 139, 255},
            )
        }
        surround := facade_style == 2 ? canvas2d.Color{166, 171, 151, 255} : canvas2d.Color{190, 166, 128, 255}
        if (structure.seed >> 19) & 1 != 0 {
            surround = facade_style == 2 ? canvas2d.Color{178, 181, 158, 255} : canvas2d.Color{205, 181, 143, 255}
        }
        if mixed_use do surround = {75, 91, 87, 255}
        frame_width: f32 = mixed_use ? .08 : .12
        frame_height := door_height + .30
        frame_offset := door_width * .5 + frame_width * .5
        left_frame_x, left_frame_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            -frame_offset,
            structure.depth * .5 + .34,
            structure.rotation,
        )
        right_frame_x, right_frame_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            frame_offset,
            structure.depth * .5 + .34,
            structure.rotation,
        )
        world_box_rotated(
            {left_frame_x, door_center_y + .08, left_frame_z},
            {frame_width, frame_height, .12},
            structure.rotation,
            surround,
        )
        world_box_rotated(
            {right_frame_x, door_center_y + .08, right_frame_z},
            {frame_width, frame_height, .12},
            structure.rotation,
            surround,
        )
        lintel_x, lintel_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .34,
            structure.rotation,
        )
        world_box_rotated(
            {lintel_x, structure.base_y + step_height + door_height + .22, lintel_z},
            {door_width + .34, .14, .14},
            structure.rotation,
            surround,
        )
        if !mixed_use && structure.seed % 5 == 3 {
            portal_x, portal_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .46,
                structure.rotation,
            )
            world_box_rotated(
                {portal_x, structure.base_y + step_height + door_height + .42, portal_z},
                {door_width + .88, .24, .42},
                structure.rotation,
                surround,
            )
            world_box_rotated(
                {portal_x, structure.base_y + step_height + door_height + .57, portal_z},
                {.34, .22, .46},
                structure.rotation,
                formation_face_color(surround, math.PI, 0),
            )
        }
        step_x, step_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .28,
            structure.rotation,
        )
        step_color :=
            facade_style == 2 ? canvas2d.Color{103, 130, 125, 255} : facade_style == 3 ? canvas2d.Color{178, 127, 88, 255} : canvas2d.Color{178, 127, 88, 255}
        if (structure.seed >> 13) & 1 != 0 {
            step_color = facade_style == 2 ? canvas2d.Color{121, 137, 126, 255} : canvas2d.Color{157, 137, 108, 255}
        }
        world_box_rotated(
            {step_x, structure.base_y + step_height * .5, step_z},
            {door_width + .72, step_height, .42},
            structure.rotation,
            step_color,
        )
        lower_step_x, lower_step_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .52,
            structure.rotation,
        )
        world_box_rotated(
            {lower_step_x, structure.base_y + .06, lower_step_z},
            {door_width + 1.05, .12, .72},
            structure.rotation,
            formation_face_color(step_color, math.PI, 0),
        )
        for paver in 0 ..< 3 {
            paver_x, paver_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .72 + f32(paver) * .36,
                structure.rotation,
            )
            paver_tone := paver % 2 == 0 ? step_color : formation_face_color(step_color, math.PI, 0)
            if (structure.seed >> 14) & 1 != 0 && paver == 1 {
                paver_tone = facade_style == 2 ? canvas2d.Color{116, 126, 116, 255} : canvas2d.Color{149, 119, 91, 255}
            }
            world_box_rotated(
                {paver_x, structure.base_y + .035, paver_z},
                {door_width + .42 - f32(paver) * .08, .07, .42},
                structure.rotation,
                paver_tone,
            )
        }
        wear_color := formation_face_color(stone, math.PI, 0)
        for wear_side in -1 ..= 1 {
            if wear_side == 0 do continue
            wear_x, wear_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(wear_side) * (door_width * .5 + .30),
                structure.depth * .5 + .145,
                structure.rotation,
            )
            world_box_rotated(
                {wear_x, structure.base_y + .42, wear_z},
                {.34, .46 + f32((structure.seed >> 5) & 1) * .12, .035},
                structure.rotation,
                wear_color,
            )
        }
        if habitable && !mixed_use && structure.seed % 2 == 0 {
            for pot_side in -1 ..= 1 {
                if pot_side == 0 do continue
                if (structure.seed >> 15) & 3 == 1 && pot_side > 0 do continue
                if (structure.seed >> 15) & 3 == 2 && pot_side < 0 do continue
                pot_height := .40 + f32((structure.seed >> u32(4 + pot_side + 1)) & 3) * .07
                pot_local_x := f32(pot_side) * (door_width * .5 + .72)
                pot_x, pot_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    pot_local_x,
                    structure.depth * .5 + .70,
                    structure.rotation,
                )
                world_architecture_residence_planter(
                    project,
                    pot_x,
                    pot_z,
                    structure.rotation,
                    structure.seed,
                    pot_side,
                    pot_height,
                )
            }
        }
        if structure.seed % 5 == 2 {
            crate_side := (structure.seed & 8) == 0 ? f32(-1) : f32(1)
            crate_local_x := crate_side * min(structure.width * .34, door_width * .5 + 2.0)
            crate_x, crate_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                crate_local_x,
                structure.depth * .5 + .62,
                structure.rotation,
            )
            world_box_rotated(
                {crate_x, structure.base_y + .30, crate_z},
                {.82, .60, .64},
                structure.rotation,
                {139, 94, 57, 255},
            )
            for slat in -1 ..= 1 {
                slat_x, slat_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    crate_local_x,
                    structure.depth * .5 + .96,
                    structure.rotation,
                )
                world_box_rotated(
                    {slat_x, structure.base_y + .30 + f32(slat) * .18, slat_z},
                    {.74, .055, .04},
                    structure.rotation,
                    {102, 71, 48, 255},
                )
            }
        }
        if structure.width >= 18 && structure.seed % 7 == 3 {
            bench_side := (structure.seed & 16) == 0 ? f32(-1) : f32(1)
            bench_local_x := bench_side * min(structure.width * .32, door_width * .5 + 2.7)
            bench_x, bench_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                bench_local_x,
                structure.depth * .5 + .78,
                structure.rotation,
            )
            // The structure is seated at the highest terrain point beneath
            // its footprint. Furniture stands outside that footprint, so
            // using structure.base_y leaves it floating on downhill frontage.
            bench_ground_y := terrain.sample_surface_height(project, 0, bench_x, bench_z)
            for ground_side in -1 ..= 1 {
                if ground_side == 0 do continue
                ground_x, ground_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    bench_local_x + f32(ground_side) * .9,
                    structure.depth * .5 + .78,
                    structure.rotation,
                )
                bench_ground_y = max(bench_ground_y, terrain.sample_surface_height(project, 0, ground_x, ground_z))
            }
            world_box_rotated(
                {bench_x, bench_ground_y + .52, bench_z},
                {2.1, .16, .58},
                structure.rotation,
                {123, 83, 55, 255},
            )
            for leg_side in -1 ..= 1 {
                if leg_side == 0 do continue
                leg_x, leg_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    bench_local_x + f32(leg_side) * .72,
                    structure.depth * .5 + .78,
                    structure.rotation,
                )
                leg_ground_y := terrain.sample_surface_height(project, 0, leg_x, leg_z)
                leg_top_y := bench_ground_y + .50
                leg_height := leg_top_y - leg_ground_y
                if leg_height > .01 {
                    world_box_rotated(
                        {leg_x, leg_ground_y + leg_height * .5, leg_z},
                        {.14, leg_height, .42},
                        structure.rotation,
                        {91, 68, 51, 255},
                    )
                }
            }
            back_x, back_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                bench_local_x,
                structure.depth * .5 + .55,
                structure.rotation,
            )
            world_box_rotated(
                {back_x, bench_ground_y + .92, back_z},
                {2.1, .52, .12},
                structure.rotation,
                {112, 77, 53, 255},
            )
        }
        mat_color := facade_style == 2 ? canvas2d.Color{72, 103, 105, 255} : canvas2d.Color{116, 73, 54, 255}
        if mixed_use {
            mat_color =
                structure.seed % 3 == 0 ? canvas2d.Color{72, 91, 86, 255} : structure.seed % 3 == 1 ? canvas2d.Color{108, 68, 58, 255} : canvas2d.Color{91, 73, 103, 255}
        }
        world_architecture_door_mat(
            structure,
            project,
            door_width,
            door_height,
            door_center_local_y,
            mat_color,
            mixed_use,
        )
        for curb_side in -1 ..= 1 {
            if curb_side == 0 do continue
            curb_x, curb_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(curb_side) * (door_width * .5 + .38),
                structure.depth * .5 + 1.10,
                structure.rotation,
            )
            world_box_rotated(
                {curb_x, structure.base_y + .09, curb_z},
                {.16, .18, 1.10},
                structure.rotation,
                formation_face_color(step_color, math.PI, 0),
            )
        }
        if structure.height < 16 && structure.seed % 5 == 0 {
            bollard_side := (structure.seed & 128) == 0 ? f32(-1) : f32(1)
            bollard_local_x := bollard_side * min(structure.width * .34, door_width * .5 + 1.65)
            bollard_x, bollard_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                bollard_local_x,
                structure.depth * .5 + 1.02,
                structure.rotation,
            )
            world_box_rotated(
                {bollard_x, structure.base_y + .46, bollard_z},
                {.28, .92, .28},
                structure.rotation,
                {85, 80, 70, 255},
            )
            world_box_rotated(
                {bollard_x, structure.base_y + .96, bollard_z},
                {.38, .10, .38},
                structure.rotation,
                {104, 94, 76, 255},
            )
        }
        if structure.seed % 6 == 1 {
            broom_side := (structure.seed & 32) == 0 ? f32(-1) : f32(1)
            broom_local_x := broom_side * (door_width * .5 + .52)
            broom_x, broom_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                broom_local_x,
                structure.depth * .5 + .48,
                structure.rotation,
            )
            world_box_rotated(
                {broom_x, structure.base_y + .88, broom_z},
                {.07, 1.62, .07},
                structure.rotation,
                {126, 91, 59, 255},
            )
            world_box_rotated(
                {broom_x, structure.base_y + .15, broom_z},
                {.52, .22, .18},
                structure.rotation,
                {160, 125, 72, 255},
            )
        }
        lantern_side := (structure.seed & 1) == 0 ? f32(-1) : f32(1)
        lantern_local_x := lantern_side * (door_width * .5 + .48)
        lantern_y := structure.base_y + step_height + door_height * (.68 + f32((structure.seed >> 17) & 3) * .035)
        bracket_x, bracket_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            lantern_local_x,
            structure.depth * .5 + .29,
            structure.rotation,
        )
        world_metal_box_rotated(
            {bracket_x, lantern_y + .18, bracket_z},
            {.08, .40, .10},
            structure.rotation,
            {65, 59, 52, 255},
        )
        lamp_x, lamp_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            lantern_local_x,
            structure.depth * .5 + .40,
            structure.rotation,
        )
        world_metal_box_rotated({lamp_x, lantern_y, lamp_z}, {.34, .44, .22}, structure.rotation, {65, 59, 52, 255})
        glass_x, glass_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            lantern_local_x,
            structure.depth * .5 + .525,
            structure.rotation,
        )
        world_box_rotated_material(
            {glass_x, lantern_y, glass_z},
            {.20, .26, .045},
            structure.rotation,
            {255, 172, 66, 255},
            .Emissive,
        )
        world_box_rotated({glass_x, lantern_y + .25, glass_z}, {.38, .07, .075}, structure.rotation, {65, 59, 52, 255})
        plaque_local_x := -lantern_side * (door_width * .5 + .40)
        plaque_x, plaque_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            plaque_local_x,
            structure.depth * .5 + .355,
            structure.rotation,
        )
        plaque_y := structure.base_y + step_height + door_height * .62
        world_box_rotated({plaque_x, plaque_y, plaque_z}, {.34, .22, .055}, structure.rotation, {202, 184, 145, 255})
        plaque_marks := 1 + int((structure.seed >> 4) % 3)
        for mark in 0 ..< plaque_marks {
            mark_offset := (f32(mark) - f32(plaque_marks - 1) * .5) * .09
            mark_x, mark_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                plaque_local_x + mark_offset,
                structure.depth * .5 + .39,
                structure.rotation,
            )
            world_box_rotated({mark_x, plaque_y, mark_z}, {.035, .11, .025}, structure.rotation, {75, 68, 58, 255})
        }
        postal := identity.archetype == .Post_Office
        if postal || structure.seed % 4 == 1 {
            mailbox_x, mailbox_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                plaque_local_x,
                structure.depth * .5 + .40,
                structure.rotation,
            )
            world_box_rotated(
                {mailbox_x, structure.base_y + step_height + door_height * .38, mailbox_z},
                {.48, .34, .18},
                structure.rotation,
                {76, 91, 91, 255},
            )
            world_box_rotated(
                {mailbox_x, structure.base_y + step_height + door_height * .44, mailbox_z},
                {.34, .035, .20},
                structure.rotation,
                {189, 174, 143, 255},
            )
        }
        if !mixed_use && structure.seed % 8 == 5 {
            urn_side := -lantern_side
            urn_local_x := urn_side * min(structure.width * .30, door_width * .5 + 1.55)
            urn_x, urn_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                urn_local_x,
                structure.depth * .5 + .67,
                structure.rotation,
            )
            world_box_rotated(
                {urn_x, structure.base_y + .28, urn_z},
                {.46, .56, .46},
                structure.rotation,
                {151, 105, 66, 255},
            )
            world_box_rotated(
                {urn_x, structure.base_y + .60, urn_z},
                {.58, .10, .58},
                structure.rotation,
                {176, 122, 74, 255},
            )
        }
        // A handful of low-rise blocks read as village shops: a shallow
        // canvas canopy over the entrance adds the lived-in 1940s street
        // rhythm without turning every façade into a storefront.
        world_architecture_storefront(structure, identity, door_width, door_height, step_height)

    }
}
