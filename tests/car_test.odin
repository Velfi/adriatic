package tests

import vehicles "../packages/vehicles"
import "core:testing"

@(test)
simple_car_has_valid_wireframe_indices :: proc(t: ^testing.T) {
	car := vehicles.simple_car()
	for edge in car.edges {
		testing.expect(t, edge.a >= 0 && edge.a < len(car.vertices))
		testing.expect(t, edge.b >= 0 && edge.b < len(car.vertices))
	}
}

@(test)
simple_car_has_a_raised_cabin_and_wheels :: proc(t: ^testing.T) {
	car := vehicles.simple_car()
	testing.expect(t, car.vertices[12].position[1] > car.vertices[4].position[1])
	testing.expect(t, car.vertices[16].position[1] < car.vertices[0].position[1])
	testing.expect(t, car.vertices[24].position[2] > car.vertices[16].position[2])
}
