package main

import "core:math"
import "core:math/linalg"
import "core:testing"

when ODIN_TEST {
    @(test)
    mouse_body_softness_capsule_has_local_falloff_and_clamp :: proc(t: ^testing.T) {
        state: Mouse_Body_Softness_State
        mouse_body_softness_reset(&state, 1)
        mouse_body_softness_accumulate_capsule(&state, {}, 0, {-.12, .31, .04}, {-.24, .18, .18}, 1, .16)

        affected := 0
        maximum := f32(0)
        for ring in 0 ..< MOUSE_BODY_RING_COUNT {
            for segment in 0 ..< MOUSE_BODY_SEGMENT_COUNT {
                length := linalg.length(state.target[ring][segment])
                if length > .0001 do affected += 1
                maximum = max(maximum, length)
            }
        }
        testing.expect(t, affected > 0)
        testing.expect(t, affected < MOUSE_BODY_RING_COUNT * MOUSE_BODY_SEGMENT_COUNT)
        testing.expect(t, maximum <= .06501)
    }

    @(test)
    mouse_body_softness_spring_converges_and_resets_invalid_steps :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        editor.tweak = tweak_default_state()
        editor.player_placement_revision = 7
        mouse_body_softness_reset(&editor.player_body_softness, 7)
        editor.player_body_softness.target[4][0] = {-.04, 0, 0}

        for _ in 0 ..< 30 {
            mouse_body_softness_update(editor, f32(1.0 / 60.0))
            editor.player_body_softness.target[4][0] = {-.04, 0, 0}
        }
        displacement := editor.player_body_softness.displacement[4][0]
        testing.expect(t, mouse_body_softness_vec_finite(displacement))
        testing.expect(
            t,
            linalg.length(displacement) <= editor.tweak.player_animation.body_softness_max_displacement + .0001,
        )
        testing.expect(t, displacement.x < -.005)

        mouse_body_softness_update(editor, .5)
        testing.expect(t, editor.player_body_softness.initialized)
        testing.expect(t, linalg.length(editor.player_body_softness.displacement[4][0]) == 0)
        testing.expect(t, !math.is_nan(editor.player_body_softness.displacement[4][0].x))
    }
}
