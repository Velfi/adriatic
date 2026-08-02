package main

import buildings "../packages/buildings"
import terrain "../packages/terrain"
import canvas2d "zelda_engine:canvas2d"

world_architecture_roof_crown :: proc(
    structure: terrain.Structure,
    identity: buildings.Identity,
    landmark, primary_mass, tower_landmark: bool,
    eave_y, rise: f32,
    terracotta: canvas2d.Color,
) {
    if tower_landmark {
        crown_height := f32(7)
        world_box_rotated(
            {structure.center_x, eave_y + rise + crown_height * .5, structure.center_z},
            {3.5, crown_height, 3.5},
            structure.rotation,
            {224, 219, 196, 255},
        )
        world_architecture_pyramid_cap(
            structure.center_x,
            structure.center_z,
            eave_y + rise + crown_height,
            4.1,
            4.1,
            structure.rotation,
            2.4,
            terracotta,
        )
    } else if identity.archetype == .Church && landmark && primary_mass {
        crown_height := f32(3.8)
        crown_width := f32(2.6)
        crown_depth := f32(2.2)
        crown_base_y := eave_y + rise
        world_box_rotated(
            {structure.center_x, crown_base_y + crown_height * .5, structure.center_z},
            {crown_width, crown_height, crown_depth},
            structure.rotation,
            {224, 219, 196, 255},
        )
        // A compound church is rendered one mass at a time. Keep the bell
        // crown on the frontage mass only, then give that otherwise blank
        // volume one restrained high lancet on each exposed face.
        lancet_color := canvas2d.Color{54, 72, 77, 255}
        lancet_y := crown_base_y + crown_height * .57
        lancet_width := f32(.52)
        lancet_height := f32(1.28)
        surface_offset := f32(.025)
        for side in -1 ..= 1 {
            if side == 0 do continue
            front_x, front_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                f32(side) * (crown_depth * .5 + surface_offset),
                structure.rotation,
            )
            world_box_rotated(
                {front_x, lancet_y, front_z},
                {lancet_width, lancet_height, .05},
                structure.rotation,
                lancet_color,
            )
            side_x, side_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(side) * (crown_width * .5 + surface_offset),
                0,
                structure.rotation,
            )
            world_box_rotated(
                {side_x, lancet_y, side_z},
                {.05, lancet_height, lancet_width},
                structure.rotation,
                lancet_color,
            )
        }
        world_architecture_pyramid_cap(
            structure.center_x,
            structure.center_z,
            eave_y + rise + crown_height,
            3.15,
            2.75,
            structure.rotation,
            1.65,
            terracotta,
        )
    }
}
