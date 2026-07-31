package fog_field

import atmosphere "../atmosphere"
import "core:testing"

@(test)
generation_is_deterministic_and_bounded :: proc(t: ^testing.T) {
    weather := atmosphere.weather_for(.Storm)
    bounds := World_Bounds{{-5000, -4000}, {5000, 4000}}
    a := generate(1234, 42, weather, bounds)
    b := generate(1234, 42, weather, bounds)
    testing.expect(t, a == b)
    for bank in a.banks {
        testing.expect(t, bank.radii.x > 0 && bank.radii.y > 0)
        testing.expect(t, bank.top_altitude > bank.base_altitude)
        testing.expect(t, bank.peak_density >= 0 && bank.peak_density <= 1)
    }
}

@(test)
clear_weather_suppresses_banks :: proc(t: ^testing.T) {
    field := generate(9, 12, atmosphere.weather_for(.Clear), {{-1000, -1000}, {1000, 1000}})
    testing.expect(t, field.global_density <= .02)
}

@(test)
sample_has_altitude_falloff_and_finite_hostile_inputs :: proc(t: ^testing.T) {
    field := generate(7, 10, atmosphere.weather_for(.Storm), {{-1000, -1000}, {1000, 1000}})
    bank := field.banks[0]
    inside := sample(field, {bank.center.x, (bank.base_altitude + bank.top_altitude) * .5, bank.center.y})
    above := sample(field, {bank.center.x, bank.top_altitude + 100, bank.center.y})
    testing.expect(t, inside >= above)
    hostile := generate(2, -100, {}, {{0, 0}, {0, 0}})
    hostile_sample := sample(hostile, {0, 0, 0})
    testing.expect(t, hostile_sample == hostile_sample && abs(hostile_sample) <= 1)
}

@(test)
adriatic_regimes_build_and_clear_fog :: proc(t: ^testing.T) {
    weather := atmosphere.regime_weather(.Jugo)
    bounds := World_Bounds{{-1000, -1000}, {1000, 1000}}
    jugo := generate(33, 20, weather, bounds, .Jugo)
    bura := generate(33, 20, weather, bounds, .Bura_Clear)
    testing.expect(t, jugo.global_density > bura.global_density)
    testing.expect(t, bura.global_density < .1)
}
