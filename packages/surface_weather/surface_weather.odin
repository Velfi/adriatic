package surface_weather

import "core:math"

RESOLUTION :: 32
CELL_COUNT :: RESOLUTION * RESOLUTION

Field :: struct {
    wetness:     [CELL_COUNT]f32,
    cursor:      int,
    half_extent: f32,
}

initialize :: proc(field: ^Field, half_extent: f32) {
    if field == nil do return
    field^ = {}
    field.half_extent = max(half_extent, f32(1))
}

cell_position :: proc(field: ^Field, index: int) -> [2]f32 {
    if field == nil || index < 0 || index >= CELL_COUNT do return {}
    x, z := index % RESOLUTION, index / RESOLUTION
    span := field.half_extent * 2
    return {
        -field.half_extent + (f32(x) + .5) / RESOLUTION * span,
        -field.half_extent + (f32(z) + .5) / RESOLUTION * span,
    }
}

step_cell :: proc(
    field: ^Field,
    index: int,
    precipitation, daylight, wind_speed, temperature_tendency, elapsed_seconds: f32,
) {
    if field == nil || index < 0 || index >= CELL_COUNT || elapsed_seconds <= 0 do return
    rain_gain := clamp(precipitation, 0, 1) * .070
    drying := .0015 + clamp(daylight, 0, 1) * .0035 + clamp(wind_speed / 20, 0, 1) * .003
    drying += clamp(temperature_tendency, 0, 1) * .0015
    field.wetness[index] = clamp(field.wetness[index] + (rain_gain - drying) * elapsed_seconds, 0, 1)
}

sample :: proc(field: ^Field, x, z: f32) -> f32 {
    if field == nil || field.half_extent <= 0 do return 0
    span := field.half_extent * 2
    gx := clamp((x + field.half_extent) / span * RESOLUTION - .5, 0, f32(RESOLUTION - 1))
    gz := clamp((z + field.half_extent) / span * RESOLUTION - .5, 0, f32(RESOLUTION - 1))
    x0, z0 := int(math.floor(f64(gx))), int(math.floor(f64(gz)))
    x1, z1 := min(x0 + 1, RESOLUTION - 1), min(z0 + 1, RESOLUTION - 1)
    tx, tz := gx - f32(x0), gz - f32(z0)
    a := field.wetness[z0 * RESOLUTION + x0]
    b := field.wetness[z0 * RESOLUTION + x1]
    c := field.wetness[z1 * RESOLUTION + x0]
    d := field.wetness[z1 * RESOLUTION + x1]
    return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * tz
}
