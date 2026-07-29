package main

import terrain "../packages/terrain"
import "core:math"
import "core:testing"

@(test)
lighthouse_beam_visibility_tracks_the_rendered_sweep :: proc(t: ^testing.T) {
    structure := terrain.structure_make(12, -8, 9, 9, 0, 22)
    structure.seed = 0
    elapsed := f32(0)
    angle := world_lighthouse_beam_angle(structure, elapsed)
    forward_x, forward_z := math.sin(angle), math.cos(angle)
    right_x, right_z := forward_z, -forward_x

    testing.expect_value(
        t,
        world_lighthouse_beam_visibility(
            structure,
            structure.center_x + forward_x * 32,
            structure.center_z + forward_z * 32,
            elapsed,
        ),
        f32(1),
    )
    testing.expect_value(
        t,
        world_lighthouse_beam_visibility(
            structure,
            structure.center_x + right_x * 32,
            structure.center_z + right_z * 32,
            elapsed,
        ),
        f32(0),
    )
    testing.expect_value(
        t,
        world_lighthouse_beam_visibility(
            structure,
            structure.center_x + forward_x * 80,
            structure.center_z + forward_z * 80,
            elapsed,
        ),
        f32(0),
    )
}
