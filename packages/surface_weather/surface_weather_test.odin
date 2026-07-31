package surface_weather

import "core:testing"

when ODIN_TEST {
    @(test)
    wetness_accumulates_drains_and_interpolates :: proc(t: ^testing.T) {
        field: Field
        initialize(&field, 4000)
        center := (RESOLUTION / 2) * RESOLUTION + RESOLUTION / 2
        step_cell(&field, center, 1, 0, 2, 0, 10)
        wet := field.wetness[center]
        testing.expect(t, wet > 0)
        step_cell(&field, center, 0, 1, 20, 1, 10)
        testing.expect(t, field.wetness[center] < wet)
        position := cell_position(&field, center)
        testing.expect(t, sample(&field, position.x, position.y) > 0)
    }
}
