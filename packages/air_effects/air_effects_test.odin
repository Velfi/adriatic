package air_effects

import "core:testing"

@(test)
rain_streaks_require_local_precipitation :: proc(t: ^testing.T) {
    testing.expect(t, rain_streak_visibility(0) == 0)
    testing.expect(t, rain_streak_visibility(.08) == 0)
    testing.expect(t, rain_streak_visibility(.29) > 0)
    testing.expect(t, rain_streak_visibility(.5) == 1)
}
