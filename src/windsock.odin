package main

import third_person "../packages/third_person"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

WINDSOCK_POLE_HEIGHT :: f32(8.5)
WINDSOCK_SECTION_COUNT :: 6
WINDSOCK_METERS_PER_SECOND_PER_BAND :: f32(1.3)

windsock_smoothstep :: #force_inline proc(edge_0, edge_1, value: f32) -> f32 {
    amount := clamp((value - edge_0) / (edge_1 - edge_0), f32(0), f32(1))
    return amount * amount * (3 - 2 * amount)
}

windsock_ring_point :: #force_inline proc(
    center, axis, side: third_person.Vec3,
    radius, angle: f32,
) -> third_person.Vec3 {
    // side and the second radial vector span the plane perpendicular to the
    // sock axis. Keeping the first vector horizontal prevents the bands from
    // rolling as their articulated centerline droops.
    second := third_person.Vec3 {
        axis.y * side.z - axis.z * side.y,
        axis.z * side.x - axis.x * side.z,
        axis.x * side.y - axis.y * side.x,
    }
    return center + side * (math.cos(angle) * radius) + second * (math.sin(angle) * radius)
}

windsock_tube :: proc(from, to: third_person.Vec3, from_radius, to_radius: f32, color: canvas2d.Color) {
    delta := to - from
    length := f32(math.sqrt(f64(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)))
    if length <= .001 do return
    axis := delta / length
    horizontal_length := f32(math.sqrt(f64(axis.x * axis.x + axis.z * axis.z)))
    side :=
        horizontal_length > .001 ? third_person.Vec3{-axis.z / horizontal_length, 0, axis.x / horizontal_length} : third_person.Vec3{1, 0, 0}
    SEGMENTS :: 12
    for segment in 0 ..< SEGMENTS {
        angle_0 := f32(segment) * math.TAU / f32(SEGMENTS)
        angle_1 := f32(segment + 1) * math.TAU / f32(SEGMENTS)
        world_quad(
            windsock_ring_point(from, axis, side, from_radius, angle_0),
            windsock_ring_point(to, axis, side, to_radius, angle_0),
            windsock_ring_point(to, axis, side, to_radius, angle_1),
            windsock_ring_point(from, axis, side, from_radius, angle_1),
            color,
        )
    }
}

windsock_mouth_ring :: proc(center, axis: third_person.Vec3) {
    length := f32(math.sqrt(f64(axis.x * axis.x + axis.z * axis.z)))
    horizontal_axis :=
        length > .001 ? third_person.Vec3{axis.x / length, 0, axis.z / length} : third_person.Vec3{1, 0, 0}
    // Two short tapered tubes leave a visible galvanized rim without closing
    // the mouth of the instrument.
    windsock_tube(center - horizontal_axis * .055, center + horizontal_axis * .055, .59, .59, {224, 219, 207, 255})
    windsock_tube(center - horizontal_axis * .061, center + horizontal_axis * .061, .49, .49, {81, 91, 96, 255})
}

world_procedural_windsock :: proc(editor: ^Editor, base: third_person.Vec3, phase: f32 = 0) {
    if editor == nil do return

    metal := canvas2d.Color{89, 99, 106, 255}
    pole_center := base + third_person.Vec3{0, WINDSOCK_POLE_HEIGHT * .5, 0}
    world_vertical_prism(pole_center, .18, .12, WINDSOCK_POLE_HEIGHT, math.PI / 8, metal)
    cap_center := base + third_person.Vec3{0, WINDSOCK_POLE_HEIGHT + .14, 0}
    world_vertical_prism(cap_center, .21, .18, .28, math.PI / 8, {211, 197, 157, 255})

    local := atmosphere_local_weather(editor, base + third_person.Vec3{0, WINDSOCK_POLE_HEIGHT, 0})
    wind := [2]f32{local.wind[0], local.wind[2]}
    speed := f32(math.sqrt(f64(wind.x * wind.x + wind.y * wind.y)))
    direction := speed > .05 ? third_person.Vec3{wind.x / speed, 0, wind.y / speed} : third_person.Vec3{1, 0, 0}
    mouth := base + third_person.Vec3{0, WINDSOCK_POLE_HEIGHT, 0}
    windsock_mouth_ring(mouth, direction)

    red := canvas2d.Color{217, 75, 50, 255}
    cream := canvas2d.Color{240, 230, 207, 255}
    section_from := mouth
    section_direction := direction
    for section in 0 ..< WINDSOCK_SECTION_COUNT {
        along := f32(section + 1) / f32(WINDSOCK_SECTION_COUNT)
        band_start := f32(section) * WINDSOCK_METERS_PER_SECOND_PER_BAND
        support := windsock_smoothstep(band_start, band_start + WINDSOCK_METERS_PER_SECOND_PER_BAND, speed)
        droop := .20 + (.008 - .20) * support
        gust :=
            math.sin(editor.map_time * (2.2 + speed * .12) + phase + f32(section) * .72) *
            (.018 + speed * .0018) *
            support *
            along
        flutter :=
            math.sin(editor.map_time * (5.8 + speed * .20) + phase * 1.7 + f32(section) * 1.31) * .02 * support * along
        section_direction =
            section_direction + third_person.Vec3{-direction.z * flutter, -droop + gust, direction.x * flutter}
        direction_length := f32(
            math.sqrt(
                f64(
                    section_direction.x * section_direction.x +
                    section_direction.y * section_direction.y +
                    section_direction.z * section_direction.z,
                ),
            ),
        )
        section_direction /= direction_length
        section_to := section_from + section_direction * 1.05
        from_radius := .52 + (.16 - .52) * (f32(section) / f32(WINDSOCK_SECTION_COUNT))
        to_radius := .52 + (.09 - .52) * (f32(section + 1) / f32(WINDSOCK_SECTION_COUNT))
        windsock_tube(section_from, section_to, from_radius, to_radius, section & 1 == 0 ? red : cream)
        section_from = section_to
    }
}
