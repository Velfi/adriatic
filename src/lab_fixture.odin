package main

import "core:math"

// Durable fixture configuration for authoring labs. Runtime scene identity and
// generated lab state remain on Editor.
Lab_Kind :: enum u8 {
    None,
    Dunes,
}

Dunes_Lab_Config :: struct {
    seed:       u32,
    wind_angle: f32,
    vegetation: f32,
}

Lab_Fixture_State :: struct {
    kind:  Lab_Kind,
    dunes: Dunes_Lab_Config,
}

lab_fixture_scalar_finite :: #force_inline proc(value: f32) -> bool {
    return value == value && !math.is_inf_f32(value)
}

// Return the precise durable-state path which prevents a lab from being
// rehydrated. This does no allocation and is safe before an Editor mutation.
lab_fixture_preflight :: proc(lab: Lab_Fixture_State) -> string {
    switch lab.kind {
    case .None:
        return ""
    case .Dunes:
        if !lab_fixture_scalar_finite(lab.dunes.wind_angle) do return "lab.dunes.wind_angle"
        if lab.dunes.wind_angle < -.62 || lab.dunes.wind_angle > .62 do return "lab.dunes.wind_angle"
        if !lab_fixture_scalar_finite(lab.dunes.vegetation) do return "lab.dunes.vegetation"
        if lab.dunes.vegetation < 0 || lab.dunes.vegetation > 1 do return "lab.dunes.vegetation"
        return ""
    }
    return "lab.kind"
}
