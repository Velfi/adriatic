package cinematic

import "core:testing"

@(test)
playback_samples_camera_and_crosses_cut_under_wipe :: proc(t: ^testing.T) {
    shots := [?]Shot {
        move("approach", 2, camera({0, 2, 10}, {0, 1, 0}), camera({0, 3, 5}, {0, 1, 0}), .Smooth, wipe(.Left, 1)),
        hold("arrival", 2, camera({10, 2, 0}, {0, 1, 0})),
    }
    script := Script {
        id    = "test",
        shots = shots[:],
    }
    playback: Playback
    testing.expect(t, play(&playback, &script))

    step(&playback, 1.75)
    covered := sample(&playback)
    testing.expect(t, covered.shot_index == 0)
    testing.expect(t, covered.wipe.kind == .Left)
    testing.expect(t, covered.wipe_progress > 0 && covered.wipe_progress < .5)
    testing.expect(t, covered.camera_from.position[0] != covered.camera_to.position[0])
    testing.expect(t, covered.camera_to.position[0] == 10)

    step(&playback, .25)
    cut := sample(&playback)
    testing.expect(t, cut.shot_index == 1)
    testing.expect(t, cut.wipe_progress == .5)
    testing.expect(t, cut.camera.position[0] == 10)
    testing.expect(t, cut.camera_from.position[0] == 0)
    testing.expect(t, cut.camera_to.position[0] == 10)

    step(&playback, .25)
    reveal := sample(&playback)
    testing.expect(t, reveal.wipe_progress > .5 && reveal.wipe_progress < 1)
}

@(test)
playback_consumes_large_steps_and_completes :: proc(t: ^testing.T) {
    value := camera({}, {0, 0, -1})
    shots := [?]Shot{hold("one", .1, value), hold("two", .2, value), hold("three", .3, value)}
    script := Script {
        shots = shots[:],
    }
    playback: Playback
    testing.expect(t, play(&playback, &script))
    step(&playback, 1)
    testing.expect(t, playback.completed)
    testing.expect(t, !playback.playing)
    testing.expect(t, playback.shot_index == 2)
}

@(test)
zero_duration_loop_is_rejected :: proc(t: ^testing.T) {
    value := camera({}, {0, 0, -1})
    shots := [?]Shot{hold("still", 0, value)}
    script := Script {
        shots = shots[:],
        loop  = true,
    }
    playback: Playback
    testing.expect(t, !play(&playback, &script))
}
