package main

import terrain "../packages/terrain"
import canvas2d "zelda_engine:canvas2d"

world_architecture_mixed_use_glass_door :: proc(
    structure: terrain.Structure,
    mixed_use: bool,
    door, panel_color: canvas2d.Color,
    door_width, door_height, door_center_y, step_height: f32,
) {
    if mixed_use {
        glass_door_x, glass_door_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .315,
            structure.rotation,
        )
        door_interior, door_interior_light := world_architecture_window_interior(structure, .Front, 0, 99, true)
        door_backing_x, door_backing_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .275,
            structure.rotation,
        )
        // Keep the door visually transparent in daylight. A bright
        // emissive slab directly behind the glass made the entrance read
        // as a cream solid leaf; this dark recessed vestibule lets the
        // warm interior light live in the glass instead.
        door_recess := color_lerp(canvas2d.Color{31, 51, 52, 255}, door_interior, .18)
        world_box_rotated(
            {door_backing_x, door_center_y + .08, door_backing_z},
            {door_width * .84, door_height * .86, .025},
            structure.rotation,
            door_recess,
        )
        door_glass_x, door_glass_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .355,
            structure.rotation,
        )
        world_glass_panel(
            {door_glass_x, door_center_y + .08, door_glass_z},
            door_width * .80,
            door_height * .82,
            structure.rotation,
            // The vestibule is shallower and less directly lit than the
            // display bays. Retaining more blue-green glass at night
            // keeps this central leaf transparent instead of becoming a
            // flat luminous slab.
            color_lerp(canvas2d.Color{34, 69, 74, 255}, door_interior, .18),
            door_interior_light * .40,
        )
        door_reflection_x, door_reflection_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            -door_width * .22,
            structure.depth * .5 + .412,
            structure.rotation,
        )
        world_box_rotated(
            {door_reflection_x, door_center_y + door_height * .08, door_reflection_z},
            {.045, door_height * .34, .022},
            structure.rotation,
            {116, 151, 151, 255},
        )
        world_box_rotated(
            {glass_door_x, door_center_y + .08, glass_door_z},
            {.065, door_height * .84, .065},
            structure.rotation,
            {188, 171, 137, 255},
        )
        world_box_rotated(
            {glass_door_x, door_center_y + door_height * .20, glass_door_z},
            {door_width * .82, .065, .065},
            structure.rotation,
            {188, 171, 137, 255},
        )
        placard_x, placard_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .405,
            structure.rotation,
        )
        placard_y := door_center_y + .16
        world_box_rotated({placard_x, placard_y, placard_z}, {.52, .32, .045}, structure.rotation, {65, 77, 73, 255})
        placard_inset_x, placard_inset_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .432,
            structure.rotation,
        )
        world_box_rotated(
            {placard_inset_x, placard_y, placard_inset_z},
            {.40, .22, .025},
            structure.rotation,
            {218, 191, 132, 255},
        )
        placard_marks := 2 + int((structure.seed >> 13) % 2)
        for mark in 0 ..< placard_marks {
            mark_x, mark_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                (f32(mark) - f32(placard_marks - 1) * .5) * .105,
                structure.depth * .5 + .448,
                structure.rotation,
            )
            world_box_rotated(
                {mark_x, placard_y, mark_z},
                {.055, .075 + f32(mark % 2) * .035, .018},
                structure.rotation,
                {84, 79, 63, 255},
            )
        }
    } else {
        for panel in 0 ..< 2 {
            panel_y := structure.base_y + step_height + (panel == 0 ? door_height * .28 : door_height * .70)
            panel_height := panel == 0 ? door_height * .34 : door_height * .26
            panel_x, panel_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .315,
                structure.rotation,
            )
            world_box_rotated(
                {panel_x, panel_y, panel_z},
                {door_width * .70, panel_height, .055},
                structure.rotation,
                panel_color,
            )
        }
    }
}
