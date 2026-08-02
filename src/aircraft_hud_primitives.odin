package main

import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

@(no_instrumentation)
aircraft_postale_part_color :: #force_inline proc(part: vehicles.Aircraft_Mesh_Part, throttle: f32) -> canvas2d.Color {
    color: canvas2d.Color
    #partial switch part {
    case .Body:
        color = {
            r = 70,
            g = 103,
            b = 76,
            a = 255,
        }
    case .Wing, .Wing_Root_Fillet, .Tail, .Left_Flap, .Right_Flap, .Left_Aileron, .Right_Aileron, .Elevator, .Rudder:
        color = {
            r = 222,
            g = 197,
            b = 126,
            a = 255,
        }
    case .Engine:
        color = {
            r = 164,
            g = 61,
            b = 48,
            a = 255,
        }
    case .Propeller:
        color = {
            r = 104,
            g = 70,
            b = 42,
            a = 255,
        }
    case .Frame:
        color = {
            r = 65,
            g = 72,
            b = 68,
            a = 255,
        }
    case .Glass:
        color = {
            r = 142,
            g = 218,
            b = 230,
            a = 190,
        }
    case .Strap:
        color = {
            r = 101,
            g = 61,
            b = 39,
            a = 255,
        }
    case .Marking:
        color = {
            r = 237,
            g = 226,
            b = 192,
            a = 255,
        }
    case .Red_Paint:
        color = {
            r = 188,
            g = 55,
            b = 45,
            a = 255,
        }
    case:
        color = aircraft_part_color(part)
    }
    blur := aircraft_propeller_blur_amount(throttle)
    if part == .Propeller || part == .Left_Propeller || part == .Right_Propeller {
        color.a = u8(clamp(255 * (1 - blur * .84), 0, 255))
    } else if part == .Propeller_Blur {
        color.a = u8(clamp(18 + blur * 26, 0, 255))
    }
    return color
}

@(no_instrumentation)
aircraft_postale_part_color_with_paint :: #force_inline proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    throttle: f32,
) -> canvas2d.Color {
    color := aircraft_postale_part_color(part, throttle)
    if part == .Propeller_Blur {
        painted := vehicle_paint_propeller_color(editor)
        color.r, color.g, color.b = painted.r, painted.g, painted.b
    }
    return color
}

@(no_instrumentation)
color_lerp :: #force_inline proc(a, b: canvas2d.Color, amount: f32) -> canvas2d.Color {
    t := clamp(amount, 0, 1)
    return {
        r = u8(f32(a.r) + (f32(b.r) - f32(a.r)) * t),
        g = u8(f32(a.g) + (f32(b.g) - f32(a.g)) * t),
        b = u8(f32(a.b) + (f32(b.b) - f32(a.b)) * t),
        a = u8(f32(a.a) + (f32(b.a) - f32(a.a)) * t),
    }
}

draw_antialiased_disc :: proc(center: canvas2d.Vector2, radius: f32, color: canvas2d.Color) {
    feather := color
    feather.a = u8(f32(color.a) * .18)
    shoulder := color
    shoulder.a = u8(f32(color.a) * .48)
    canvas2d.DrawCircleHatched(center, radius + 1.25, feather, canvas2d.HATCH_DISABLED, 96)
    canvas2d.DrawCircleHatched(center, radius + .55, shoulder, canvas2d.HATCH_DISABLED, 96)
    canvas2d.DrawCircleHatched(center, radius, color, canvas2d.HATCH_DISABLED, 96)
}

draw_antialiased_line :: proc(a, b: canvas2d.Vector2, thickness: f32, color: canvas2d.Color) {
    feather := color
    feather.a = u8(f32(color.a) * .22)
    canvas2d.DrawLineEx(a, b, thickness + 1.5, feather)
    canvas2d.DrawLineEx(a, b, thickness, color)
}

draw_instrument_text :: proc(text: cstring, position: canvas2d.Vector2, size, spacing: f32, color: canvas2d.Color) {
    shadow := canvas2d.Color {
        r = 0,
        g = 7,
        b = 12,
        a = u8(235 * f32(color.a) / 255),
    }
    canvas2d.DrawTextEx(canvas2d.Font{}, text, {position.x + 1.5, position.y + 1.5}, size, spacing, shadow)
    canvas2d.DrawTextEx(canvas2d.Font{}, text, position, size, spacing, color)
}

draw_flight_console_panel :: proc(bounds: canvas2d.Rectangle, corner_radius: f32, color: canvas2d.Color) {
    radius := clamp(corner_radius, 0, min(bounds.width * .5, bounds.height))
    // Scan the upper quarter-arcs into horizontal subpixel lines. Unlike whole
    // discs, this keeps very large radii clipped to the upper corners and
    // guarantees that the installed console's lower edge remains square.
    rows := max(1, int(math.ceil(f64(radius))))
    for row in 0 ..< rows {
        vertical := radius - min(f32(row) + .5, radius)
        horizontal := f32(math.sqrt(f64(max(radius * radius - vertical * vertical, 0))))
        inset := radius - horizontal
        y := bounds.y + f32(row) + .5
        draw_antialiased_line({bounds.x + inset, y}, {bounds.x + bounds.width - inset, y}, 1, color)
    }
    canvas2d.DrawRectangle(
        i32(bounds.x),
        i32(bounds.y + radius),
        i32(bounds.width),
        i32(bounds.height - radius),
        color,
    )

    // Trace the curved shoulder as one continuous padded coaming. The warm
    // leather edge ties the panel to the Postale's cockpit upholstery while a
    // narrow cool highlight keeps the contour readable against dark scenery.
    coaming := canvas2d.Color {
        r = 84,
        g = 55,
        b = 39,
        a = 255,
    }
    edge := canvas2d.Color {
        r = 139,
        g = 115,
        b = 86,
        a = 210,
    }
    previous_left := canvas2d.Vector2{bounds.x + radius, bounds.y + .5}
    previous_right := canvas2d.Vector2{bounds.x + bounds.width - radius, bounds.y + .5}
    draw_antialiased_line(previous_left, previous_right, 4.5, coaming)
    draw_antialiased_line(previous_left, previous_right, 1.2, edge)
    for row in 1 ..< rows {
        vertical := radius - min(f32(row) + .5, radius)
        horizontal := f32(math.sqrt(f64(max(radius * radius - vertical * vertical, 0))))
        inset := radius - horizontal
        y := bounds.y + f32(row) + .5
        left := canvas2d.Vector2{bounds.x + inset, y}
        right := canvas2d.Vector2{bounds.x + bounds.width - inset, y}
        draw_antialiased_line(previous_left, left, 4.5, coaming)
        draw_antialiased_line(previous_right, right, 4.5, coaming)
        draw_antialiased_line(previous_left, left, 1.1, edge)
        draw_antialiased_line(previous_right, right, 1.1, edge)
        previous_left = left
        previous_right = right
    }
    draw_antialiased_line(
        {bounds.x + 18, bounds.y + bounds.height - 1},
        {bounds.x + bounds.width - 18, bounds.y + bounds.height - 1},
        1.2,
        {r = 2, g = 8, b = 11, a = 230},
    )
    screw := canvas2d.Color {
        r = 151,
        g = 160,
        b = 149,
        a = 230,
    }
    screw_shadow := canvas2d.Color {
        r = 3,
        g = 9,
        b = 11,
        a = 240,
    }
    screw_positions := [4]canvas2d.Vector2 {
        {bounds.x + 18, bounds.y + bounds.height - 17},
        {bounds.x + bounds.width - 18, bounds.y + bounds.height - 17},
        {bounds.x + radius * .72, bounds.y + radius * .72},
        {bounds.x + bounds.width - radius * .72, bounds.y + radius * .72},
    }
    for position in screw_positions {
        draw_antialiased_disc(position, 3.2, screw_shadow)
        draw_antialiased_disc(position, 1.8, screw)
        draw_antialiased_line(
            {position.x - 1.2, position.y + 1.2},
            {position.x + 1.2, position.y - 1.2},
            .8,
            screw_shadow,
        )
    }
}

draw_instrument_bezel :: proc(center: canvas2d.Vector2, radius: f32) {
    shadow := canvas2d.Color {
        r = 2,
        g = 8,
        b = 11,
        a = 235,
    }
    outer := canvas2d.Color {
        r = 42,
        g = 57,
        b = 59,
        a = 255,
    }
    metal := canvas2d.Color {
        r = 104,
        g = 132,
        b = 132,
        a = 235,
    }
    inner := canvas2d.Color {
        r = 19,
        g = 31,
        b = 37,
        a = 255,
    }
    face := canvas2d.Color {
        r = 9,
        g = 21,
        b = 29,
        a = 255,
    }
    draw_antialiased_disc({center.x + 1.5, center.y + 2}, radius + 7, shadow)
    draw_antialiased_disc(center, radius + 6, outer)
    draw_antialiased_disc(center, radius + 4, metal)
    draw_antialiased_disc(center, radius + 1.5, inner)
    draw_antialiased_disc(center, radius, face)
}

draw_instrument_glass :: proc(center: canvas2d.Vector2, radius: f32) {
    reflection := canvas2d.Color {
        r = 196,
        g = 236,
        b = 235,
        a = 42,
    }
    // Restrained diagonal glints imply convex glass without washing out the
    // markings or introducing a large translucent overlay.
    draw_antialiased_line(
        {center.x - radius * .56, center.y - radius * .58},
        {center.x - radius * .18, center.y - radius * .78},
        1.5,
        reflection,
    )
    draw_antialiased_line(
        {center.x - radius * .61, center.y - radius * .48},
        {center.x - radius * .44, center.y - radius * .57},
        1,
        reflection,
    )
}

draw_rounded_inset :: proc(bounds: canvas2d.Rectangle, corner_radius: f32, color: canvas2d.Color) {
    radius := clamp(corner_radius, 0, min(bounds.width, bounds.height) * .5)
    rows := max(1, int(math.ceil(f64(bounds.height))))
    for row in 0 ..< rows {
        y_local := min(f32(row) + .5, bounds.height - .5)
        inset := f32(0)
        if y_local < radius {
            vertical := radius - y_local
            inset = radius - f32(math.sqrt(f64(max(radius * radius - vertical * vertical, 0))))
        } else if y_local > bounds.height - radius {
            vertical := y_local - (bounds.height - radius)
            inset = radius - f32(math.sqrt(f64(max(radius * radius - vertical * vertical, 0))))
        }
        canvas2d.DrawLineEx(
            {bounds.x + inset, bounds.y + y_local},
            {bounds.x + bounds.width - inset, bounds.y + y_local},
            1.2,
            color,
        )
    }
}

draw_rectangular_instrument_bezel :: proc(bounds: canvas2d.Rectangle, radius: f32) -> canvas2d.Rectangle {
    draw_rounded_inset(
        {x = bounds.x + 1.5, y = bounds.y + 2, width = bounds.width, height = bounds.height},
        radius,
        {r = 2, g = 8, b = 11, a = 235},
    )
    draw_rounded_inset(bounds, radius, {r = 45, g = 60, b = 62, a = 255})
    metal_bounds := canvas2d.Rectangle {
        x      = bounds.x + 2,
        y      = bounds.y + 2,
        width  = bounds.width - 4,
        height = bounds.height - 4,
    }
    draw_rounded_inset(metal_bounds, max(radius - 2, f32(1)), {r = 104, g = 132, b = 132, a = 235})
    face_bounds := canvas2d.Rectangle {
        x      = bounds.x + 4,
        y      = bounds.y + 4,
        width  = bounds.width - 8,
        height = bounds.height - 8,
    }
    draw_rounded_inset(face_bounds, max(radius - 4, f32(1)), {r = 7, g = 19, b = 27, a = 255})
    return face_bounds
}

draw_instrument_dial :: proc(
    center: canvas2d.Vector2,
    radius: f32,
    label: cstring,
    value, minimum, maximum: f32,
    value_text: cstring,
    value_y_offset: f32 = 27,
    range_start: f32 = -1,
    range_end: f32 = -1,
    reference_value: f32 = -1,
) {
    mark := canvas2d.Color {
        r = 232,
        g = 247,
        b = 245,
        a = 255,
    }
    accent := canvas2d.Color {
        r = 239,
        g = 203,
        b = 111,
        a = 255,
    }
    draw_instrument_bezel(center, radius)
    sweep_start := f32(math.PI * .75)
    sweep_range := f32(math.PI * 1.5)
    for tick in 0 ..= 14 {
        angle := sweep_start + f32(tick) / 14 * sweep_range
        outer := canvas2d.Vector2{center.x + math.cos(angle) * (radius - 7), center.y + math.sin(angle) * (radius - 7)}
        major := tick % 7 == 0
        inner_radius := radius - (major ? f32(18) : f32(13))
        inner := canvas2d.Vector2{center.x + math.cos(angle) * inner_radius, center.y + math.sin(angle) * inner_radius}
        draw_antialiased_line(inner, outer, major ? f32(2.6) : f32(1.5), mark)
    }
    if reference_value >= minimum && reference_value <= maximum {
        reference_fraction := clamp((reference_value - minimum) / max(maximum - minimum, f32(.001)), 0, 1)
        reference_angle := sweep_start + reference_fraction * sweep_range
        reference_outer_radius := radius - 6
        reference_inner_radius := radius - 16
        reference_outer := canvas2d.Vector2 {
            center.x + math.cos(reference_angle) * reference_outer_radius,
            center.y + math.sin(reference_angle) * reference_outer_radius,
        }
        reference_inner := canvas2d.Vector2 {
            center.x + math.cos(reference_angle) * reference_inner_radius,
            center.y + math.sin(reference_angle) * reference_inner_radius,
        }
        // A small cyan index bug marks the preferred cruise altitude without
        // competing with the live amber needle or adding another dial label.
        draw_antialiased_line(reference_inner, reference_outer, 3, {r = 92, g = 219, b = 213, a = 230})
    }
    if range_start >= minimum && range_end > range_start {
        start_fraction := clamp((range_start - minimum) / max(maximum - minimum, f32(.001)), 0, 1)
        end_fraction := clamp((range_end - minimum) / max(maximum - minimum, f32(.001)), 0, 1)
        band_radius := radius - 19
        band_color := canvas2d.Color {
            r = 92,
            g = 219,
            b = 213,
            a = 180,
        }
        previous_angle := sweep_start + start_fraction * sweep_range
        previous := canvas2d.Vector2 {
            center.x + math.cos(previous_angle) * band_radius,
            center.y + math.sin(previous_angle) * band_radius,
        }
        for segment in 1 ..= 14 {
            fraction := start_fraction + (end_fraction - start_fraction) * f32(segment) / 14
            angle := sweep_start + fraction * sweep_range
            point := canvas2d.Vector2 {
                center.x + math.cos(angle) * band_radius,
                center.y + math.sin(angle) * band_radius,
            }
            draw_antialiased_line(previous, point, 2, band_color)
            previous = point
        }
    }
    // Three quiet scale anchors make needle position readable at a glance
    // without crowding the compact face with a full ring of numerals.
    scale_values := [3]f32{minimum, (minimum + maximum) * .5, maximum}
    scale_fractions := [3]f32{0, .5, 1}
    for index in 0 ..< len(scale_values) {
        angle := sweep_start + scale_fractions[index] * sweep_range
        anchor_radius := radius - 20
        text := fmt.ctprintf("%.0f", scale_values[index])
        size := canvas2d.MeasureTextEx(canvas2d.Font{}, text, 9, 0)
        position := canvas2d.Vector2 {
            center.x + math.cos(angle) * anchor_radius - size.x * .5,
            center.y + math.sin(angle) * anchor_radius - size.y * .5,
        }
        draw_instrument_text(text, position, 9, 0, {r = 182, g = 207, b = 205, a = 230})
    }
    fraction := clamp((value - minimum) / max(f32(.001), maximum - minimum), 0, 1)
    needle_angle := sweep_start + fraction * sweep_range
    needle_length := radius - 23
    needle_end := canvas2d.Vector2 {
        center.x + math.cos(needle_angle) * needle_length,
        center.y + math.sin(needle_angle) * needle_length,
    }
    needle_shadow := canvas2d.Color {
        r = 1,
        g = 7,
        b = 10,
        a = 220,
    }
    draw_antialiased_line(
        {center.x + 1.5, center.y + 1.5},
        {needle_end.x + 1.5, needle_end.y + 1.5},
        4.2,
        needle_shadow,
    )
    draw_antialiased_line(center, needle_end, 3.5, accent)
    counterweight := canvas2d.Vector2{center.x - math.cos(needle_angle) * 10, center.y - math.sin(needle_angle) * 10}
    draw_antialiased_line(center, counterweight, 2.4, accent)
    draw_antialiased_disc(center, 6.2, needle_shadow)
    draw_antialiased_disc(center, 4.2, accent)
    label_size := canvas2d.MeasureTextEx(canvas2d.Font{}, label, 14, 1)
    value_size := canvas2d.MeasureTextEx(canvas2d.Font{}, value_text, 18, 1)
    draw_instrument_text(label, {center.x - label_size.x * .5, center.y - 18}, 14, 1, mark)
    draw_instrument_text(value_text, {center.x - value_size.x * .5, center.y + value_y_offset}, 18, 1, accent)
    draw_instrument_glass(center, radius)
}

draw_attitude_indicator :: proc(center: canvas2d.Vector2, radius, pitch, bank: f32) {
    mark := canvas2d.Color {
        r = 240,
        g = 248,
        b = 235,
        a = 255,
    }
    accent := canvas2d.Color {
        r = 239,
        g = 203,
        b = 111,
        a = 255,
    }
    draw_instrument_bezel(center, radius)

    scale := radius / 48
    inner_radius := radius - 4
    pitch_offset := clamp(pitch * 42 * scale, -inner_radius * .72, inner_radius * .72)
    effect := Attitude_Gauge_Effect{pitch_offset / inner_radius, bank, scale / inner_radius}
    canvas2d.draw_effect_quad(
        {center.x - inner_radius, center.y - inner_radius, inner_radius * 2, inner_radius * 2},
        {255, 255, 255, 255},
        canvas2d.effect_payload(ATTITUDE_GAUGE_EFFECT, &effect),
    )

    // Fixed bank scale and lubber pointer make roll readable even when the
    // horizon is near the edge of the dial.
    bank_marks := [5]f32{-60, -30, 0, 30, 60}
    for degrees in bank_marks {
        angle := -math.PI * .5 + degrees * math.PI / 180
        outer := canvas2d.Vector2{center.x + math.cos(angle) * (radius - 7), center.y + math.sin(angle) * (radius - 7)}
        inner := canvas2d.Vector2 {
            center.x + math.cos(angle) * (radius - (degrees == 0 ? f32(16) : f32(12))),
            center.y + math.sin(angle) * (radius - (degrees == 0 ? f32(16) : f32(12))),
        }
        draw_antialiased_line(inner, outer, degrees == 0 ? f32(2.5) : f32(1.5), mark)
    }

    // Fixed miniature-aircraft symbol.
    draw_antialiased_line({center.x - 29 * scale, center.y}, {center.x - 8 * scale, center.y}, 3.5, accent)
    draw_antialiased_line({center.x + 8 * scale, center.y}, {center.x + 29 * scale, center.y}, 3.5, accent)
    draw_antialiased_line({center.x - 8 * scale, center.y}, {center.x, center.y + 5 * scale}, 3, accent)
    draw_antialiased_line({center.x + 8 * scale, center.y}, {center.x, center.y + 5 * scale}, 3, accent)
    draw_antialiased_disc({center.x, center.y + 5 * scale}, 3.5 * scale, accent)
    draw_instrument_glass(center, radius)
}

compass_tick_label :: proc(degrees: int) -> cstring {
    heading := degrees % 360
    if heading < 0 do heading += 360
    switch heading {
    case 0:
        return "N"
    case 30:
        return "03"
    case 60:
        return "06"
    case 90:
        return "E"
    case 120:
        return "12"
    case 150:
        return "15"
    case 180:
        return "S"
    case 210:
        return "21"
    case 240:
        return "24"
    case 270:
        return "W"
    case 300:
        return "30"
    case 330:
        return "33"
    case:
        return ""
    }
}

draw_heading_compass :: proc(center: canvas2d.Vector2, width, heading_degrees: f32) {
    height := f32(42)
    outer := canvas2d.Rectangle {
        x      = center.x - width * .5,
        y      = center.y - height * .5,
        width  = width,
        height = height,
    }
    face := draw_rectangular_instrument_bezel(outer, 8)
    accent := canvas2d.Color {
        r = 239,
        g = 203,
        b = 111,
        a = 255,
    }
    nearest := int(math.round(f64(heading_degrees / 15))) * 15
    half_range := f32(52.5)
    for offset := -4; offset <= 4; offset += 1 {
        tick_heading := nearest + offset * 15
        delta := f32(tick_heading) - heading_degrees
        for delta > 180 do delta -= 360
        for delta < -180 do delta += 360
        if math.abs(delta) > half_range do continue
        x := center.x + delta / half_range * (face.width * .46)
        major := tick_heading % 30 == 0
        tick_top := face.y + (major ? f32(3) : f32(7))
        draw_antialiased_line({x, tick_top}, {x, face.y + 13}, major ? f32(1.8) : f32(1), {220, 239, 238, 255})
        if major {
            label := compass_tick_label(tick_heading)
            label_size := canvas2d.MeasureTextEx(canvas2d.Font{}, label, 11, 1)
            normalized := tick_heading % 360
            if normalized < 0 do normalized += 360
            label_color := normalized % 90 == 0 ? accent : canvas2d.Color{235, 248, 246, 255}
            draw_instrument_text(label, {x - label_size.x * .5, face.y + 15}, 11, 1, label_color)
        }
    }

    // A fixed brass lubber index sits proud of the moving heading card.
    pointer_top := outer.y + 1
    draw_antialiased_line({center.x, pointer_top + 1}, {center.x, pointer_top + 12}, 2.5, accent)
    draw_antialiased_line({center.x - 5, pointer_top + 3}, {center.x, pointer_top + 9}, 2, accent)
    draw_antialiased_line({center.x + 5, pointer_top + 3}, {center.x, pointer_top + 9}, 2, accent)
    draw_antialiased_line(
        {face.x + 12, face.y + 3},
        {face.x + face.width * .28, face.y + 3},
        1,
        {r = 196, g = 236, b = 235, a = 34},
    )
}
