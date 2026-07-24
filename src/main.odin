package main

import "core:fmt"
import zmath "zelda_engine:math"

main :: proc() {
	starting_position := zmath.Vec2 {x = 0, y = 0}
	fmt.printf("Adriatic is underway at (%.0f, %.0f).\n", starting_position.x, starting_position.y)
}
