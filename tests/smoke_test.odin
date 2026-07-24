package tests

import "core:testing"
import zmath "zelda_engine:math"

@(test)
smoke_test :: proc(t: ^testing.T) {
	position := zmath.Vec2 {
		x = 3,
		y = 4,
	}
	testing.expect(t, position.x == 3 && position.y == 4)
}
