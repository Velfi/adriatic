package main

import "core:testing"

@(test)
bomber_pip_tracks_newest_airborne_drop :: proc(t: ^testing.T) {
    drops := [3]Bomber_Drop {
        {seed = 3},
        {seed = 9},
        {seed = 6},
    }

    tracked := bomber_pip_drop_from(drops[:])
    testing.expect(t, tracked == &drops[1])

    drops[1].landed = true
    tracked = bomber_pip_drop_from(drops[:])
    testing.expect(t, tracked == &drops[2])

    drops[0].landed = true
    drops[2].landed = true
    testing.expect(t, bomber_pip_drop_from(drops[:]) == nil)
}

@(test)
bomber_pip_layout_stays_inside_narrow_viewports :: proc(t: ^testing.T) {
    viewports := [3][2]f32{{320, 240}, {640, 360}, {1280, 720}}
    for viewport in viewports {
        layout := bomber_pip_layout(viewport[0], viewport[1])
        testing.expect(t, layout.x >= 0)
        testing.expect(t, layout.y >= 0)
        testing.expect(t, layout.width > 0)
        testing.expect(t, layout.height > 0)
        testing.expect(t, layout.x + layout.width <= viewport[0])
        testing.expect(t, layout.y + layout.height <= viewport[1])
        testing.expect(t, abs(layout.width / layout.height - f32(16) / 9) < .001)
    }
}
