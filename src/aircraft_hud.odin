package main

import air_effects "../packages/air_effects"
import atmosphere "../packages/atmosphere"
import flight "../packages/flight"
import postale_game "../packages/postale"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

draw_throttle_overlay :: proc(editor: ^Editor, width, height: i32, power: f32) {
    if editor == nil do return
    normalized := clamp(power, 0, 1)
    now := canvas2d.GetTime()
    if !editor.flight_throttle_overlay_initialized {
        editor.flight_throttle_overlay_value = normalized
        editor.flight_throttle_overlay_changed_at = now
        editor.flight_throttle_overlay_fade_started_at = now
        editor.flight_throttle_overlay_initialized = true
    } else if math.abs(normalized - editor.flight_throttle_overlay_value) > .001 {
        was_hidden := now - editor.flight_throttle_overlay_changed_at >= 3
        editor.flight_throttle_overlay_value = normalized
        editor.flight_throttle_overlay_changed_at = now
        if was_hidden do editor.flight_throttle_overlay_fade_started_at = now
    }

    age := f32(now - editor.flight_throttle_overlay_changed_at)
    if age >= 3 do return
    fade_age := f32(now - editor.flight_throttle_overlay_fade_started_at)
    fade_in := clamp(fade_age / .14, 0, 1)
    fade_out := clamp((3 - age) / .65, 0, 1)
    visibility := fade_in * fade_out
    alpha := u8(clamp(255 * visibility, 0, 255))

    overlay_height := min(f32(height) * .68, f32(500))
    overlay_width := f32(52)
    outer := canvas2d.Rectangle {
        x      = f32(width) - overlay_width - 22,
        y      = (f32(height) - overlay_height) * .5,
        width  = overlay_width,
        height = overlay_height,
    }
    draw_rounded_inset(outer, 15, {r = 3, g = 12, b = 18, a = u8(f32(alpha) * .72)})
    edge := canvas2d.Color {
        r = 104,
        g = 132,
        b = 132,
        a = u8(f32(alpha) * .72),
    }
    draw_antialiased_line({outer.x + 10, outer.y + 1}, {outer.x + outer.width - 10, outer.y + 1}, 1.2, edge)

    track_top := outer.y + 45
    track_bottom := outer.y + outer.height - 30
    track_x := outer.x + outer.width * .5
    track_height := track_bottom - track_top
    draw_antialiased_line(
        {track_x, track_top},
        {track_x, track_bottom},
        8,
        {r = 7, g = 20, b = 28, a = u8(f32(alpha) * .92)},
    )
    level_y := track_bottom - normalized * track_height
    fill_color := color_lerp({r = 190, g = 132, b = 67, a = 255}, {r = 246, g = 211, b = 111, a = 255}, normalized)
    fill_color.a = alpha
    draw_antialiased_line({track_x, track_bottom}, {track_x, level_y}, 5, fill_color)
    tick_color := canvas2d.Color {
        r = 190,
        g = 211,
        b = 207,
        a = u8(f32(alpha) * .78),
    }
    for detent in 0 ..= 8 {
        y := track_top + f32(detent) / 8 * track_height
        major := detent % 2 == 0
        draw_antialiased_line(
            {track_x - (major ? f32(13) : f32(9)), y},
            {track_x - 6, y},
            major ? f32(1.3) : f32(.8),
            tick_color,
        )
    }

    // The bright sliding handle is the primary feedback; the percentage is a
    // secondary confirmation and disappears with the rest of the overlay.
    draw_antialiased_disc({track_x, level_y}, 8, {r = 6, g = 17, b = 22, a = alpha})
    draw_antialiased_line({track_x - 12, level_y}, {track_x + 12, level_y}, 4, fill_color)
    label: cstring = "THR"
    value := fmt.ctprintf("%.0f%%", normalized * 100)
    label_size := canvas2d.MeasureTextEx(canvas2d.Font{}, label, 11, 1)
    value_size := canvas2d.MeasureTextEx(canvas2d.Font{}, value, 13, 1)
    text_color := canvas2d.Color {
        r = 231,
        g = 245,
        b = 243,
        a = alpha,
    }
    draw_instrument_text(label, {track_x - label_size.x * .5, outer.y + 13}, 11, 1, text_color)
    draw_instrument_text(value, {track_x - value_size.x * .5, outer.y + outer.height - 21}, 13, 1, fill_color)
}

draw_vsi_inset :: proc(center: canvas2d.Vector2, radius, vertical_speed: f32) {
    track_x := center.x + radius * .55
    track_half_height := radius * .34
    capsule := canvas2d.Rectangle {
        x      = track_x - 10,
        y      = center.y - track_half_height - 5,
        width  = 20,
        height = track_half_height * 2 + 10,
    }
    draw_rounded_inset(capsule, 8, {r = 45, g = 60, b = 62, a = 245})
    face := canvas2d.Rectangle {
        x      = capsule.x + 2,
        y      = capsule.y + 2,
        width  = capsule.width - 4,
        height = capsule.height - 4,
    }
    draw_rounded_inset(face, 6, {r = 5, g = 17, b = 24, a = 255})

    track := canvas2d.Color {
        r = 126,
        g = 164,
        b = 168,
        a = 210,
    }
    climb := canvas2d.Color {
        r = 92,
        g = 219,
        b = 213,
        a = 255,
    }
    draw_antialiased_line({track_x, center.y - track_half_height}, {track_x, center.y + track_half_height}, 1.2, track)
    for tick in -2 ..= 2 {
        y := center.y + f32(tick) * track_half_height * .5
        tick_half := tick == 0 ? f32(5) : f32(3)
        draw_antialiased_line({track_x - tick_half, y}, {track_x + tick_half, y}, 1, track)
    }
    end_y := center.y - clamp(vertical_speed / 10, -1, 1) * track_half_height
    draw_antialiased_line({track_x, center.y}, {track_x, end_y}, 3, climb)
    draw_antialiased_line({track_x - 6, end_y}, {track_x + 6, end_y}, 2.5, climb)

    // Keep the signed rate close to its pointer rather than laying a second
    // line of text across the altimeter's main scale.
    readout := fmt.ctprintf("%+.0f", vertical_speed)
    readout_size := canvas2d.MeasureTextEx(canvas2d.Font{}, readout, 8, 0)
    readout_y := clamp(end_y - 5, capsule.y + 5, capsule.y + capsule.height - 12)
    draw_instrument_text(readout, {capsule.x - readout_size.x - 3, readout_y}, 8, 0, climb)
}

draw_rondine_instruments :: proc(editor: ^Editor, width, height: i32) {
    panel_width := min(f32(width) - 32, f32(520))
    panel_height := f32(68)
    panel_left := f32(width) * .5 - panel_width * .5
    panel_top := f32(height) - panel_height - 14
    panel := canvas2d.Rectangle{panel_left, panel_top, panel_width, panel_height}
    draw_flight_console_panel(panel, 34, {r = 10, g = 25, b = 27, a = 238})

    labels := [5]cstring{"SPEED", "SKIM", "SLIP", "DRIFT", "THROTTLE"}
    values := [5]cstring {
        fmt.ctprintf("%.0f m/s", editor.rondine.telemetry.speed),
        fmt.ctprintf("%.1f m", editor.rondine.telemetry.height),
        fmt.ctprintf("%+.0f%%", editor.rondine.telemetry.slip * 100),
        fmt.ctprintf("%.0f%%", editor.rondine.telemetry.drift_intensity * 100),
        fmt.ctprintf("%.0f%%", editor.rondine.throttle * 100),
    }
    column_width := panel_width / 5
    for label, index in labels {
        x := panel_left + column_width * (f32(index) + .5)
        if index > 0 {
            separator_x := panel_left + column_width * f32(index)
            draw_antialiased_line(
                {separator_x, panel_top + 12},
                {separator_x, panel_top + panel_height - 12},
                1,
                {94, 130, 127, 130},
            )
        }
        label_size := canvas2d.MeasureTextEx(canvas2d.Font{}, label, 9, .5)
        value_size := canvas2d.MeasureTextEx(canvas2d.Font{}, values[index], 17, .5)
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            label,
            {x - label_size.x * .5, panel_top + 12},
            9,
            .5,
            {150, 192, 187, 255},
        )
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            values[index],
            {x - value_size.x * .5, panel_top + 32},
            17,
            .5,
            {242, 221, 154, 255},
        )
    }
}

bomber_hud_ring :: proc(center: canvas2d.Vector2, radius, line_width: f32, color: canvas2d.Color) {
    segments :: 64
    previous := canvas2d.Vector2{center.x + radius, center.y}
    for segment in 1 ..= segments {
        angle := f32(segment) / f32(segments) * f32(math.PI * 2)
        next := canvas2d.Vector2 {
            center.x + f32(math.cos(f64(angle))) * radius,
            center.y + f32(math.sin(f64(angle))) * radius,
        }
        canvas2d.DrawLineEx(previous, next, line_width, color)
        previous = next
    }
}

bomber_hud_draw :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil ||
       !editor.in_map ||
       !driving_aircraft(editor) ||
       !editor.bomber_mode ||
       !editor.gameplay_options.show_hud {
        return
    }
    center := canvas2d.Vector2{f32(width) * .5, f32(height) * .5}
    radius := clamp(min(f32(width), f32(height)) * .17, f32(92), f32(155))
    sight := canvas2d.Color{232, 224, 170, 225}
    shadow := canvas2d.Color{9, 24, 25, 180}
    bomber_hud_ring(center, radius + 1, 3, shadow)
    bomber_hud_ring(center, radius, 1.5, sight)
    bomber_hud_ring(center, radius * .42, 1.5, sight)
    canvas2d.DrawLineEx({center.x - radius, center.y}, {center.x - 16, center.y}, 3, shadow)
    canvas2d.DrawLineEx({center.x + 16, center.y}, {center.x + radius, center.y}, 3, shadow)
    canvas2d.DrawLineEx({center.x, center.y - radius}, {center.x, center.y - 16}, 3, shadow)
    canvas2d.DrawLineEx({center.x, center.y + 16}, {center.x, center.y + radius}, 3, shadow)
    canvas2d.DrawLineEx({center.x - radius, center.y}, {center.x - 16, center.y}, 1.5, sight)
    canvas2d.DrawLineEx({center.x + 16, center.y}, {center.x + radius, center.y}, 1.5, sight)
    canvas2d.DrawLineEx({center.x, center.y - radius}, {center.x, center.y - 16}, 1.5, sight)
    canvas2d.DrawLineEx({center.x, center.y + 16}, {center.x, center.y + radius}, 1.5, sight)
    ready := editor.bomber_drop_cooldown <= 0
    ready_color := ready ? canvas2d.Color{111, 225, 174, 245} : canvas2d.Color{236, 190, 102, 230}
    canvas2d.DrawCircleV(center, ready ? f32(4.5) : f32(3.5), ready_color)
    if editor.bomber_release_flash > 0 {
        release_radius := 12 + (1 - editor.bomber_release_flash) * 34
        release_alpha := u8(clamp(editor.bomber_release_flash * 235, 0, 235))
        bomber_hud_ring(center, release_radius, 2.5, {111, 225, 174, release_alpha})
    }
    impact := bomber_predicted_impact(editor)
    still_air_impact := bomber_predicted_impact_for_wind(editor, false)
    body := active_aircraft_body(editor)
    dx, dz := impact.x - body.position.x, impact.z - body.position.z
    distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
    drift_x, drift_z := impact.x - still_air_impact.x, impact.z - still_air_impact.z
    drift_distance := f32(math.sqrt(f64(drift_x * drift_x + drift_z * drift_z)))
    wind_x, wind_z := editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]
    wind_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
    if drift_distance > .1 {
        camera := perspective_camera(bomber_camera_pose(editor), editor.flight_camera.focal_length)
        still_projection := project_3d(camera, still_air_impact, width, height)
        correction := canvas2d.Vector2{center.x - still_projection.position.x, center.y - still_projection.position.y}
        correction_length := f32(math.sqrt_f64(f64(correction.x * correction.x + correction.y * correction.y)))
        if correction_length > .01 {
            direction := canvas2d.Vector2{correction.x / correction_length, correction.y / correction_length}
            arrow_length := min(max(drift_distance * 1.15, f32(18)), radius * .72)
            arrow_start := canvas2d.Vector2 {
                center.x - direction.x * arrow_length,
                center.y - direction.y * arrow_length,
            }
            arrow_end := canvas2d.Vector2{center.x - direction.x * 9, center.y - direction.y * 9}
            arrow_side := canvas2d.Vector2{-direction.y, direction.x}
            canvas2d.DrawLineEx(arrow_start, arrow_end, 4, shadow)
            canvas2d.DrawLineEx(arrow_start, arrow_end, 2, {104, 210, 205, 235})
            canvas2d.DrawLineEx(
                arrow_end,
                {arrow_end.x - direction.x * 12 + arrow_side.x * 7, arrow_end.y - direction.y * 12 + arrow_side.y * 7},
                2,
                {104, 210, 205, 235},
            )
            canvas2d.DrawLineEx(
                arrow_end,
                {arrow_end.x - direction.x * 12 - arrow_side.x * 7, arrow_end.y - direction.y * 12 - arrow_side.y * 7},
                2,
                {104, 210, 205, 235},
            )
        }
    }
    readiness: cstring = ready ? "READY" : "RELOAD"
    label := fmt.ctprintf(
        "BOMBER  •  %s  •  %s  •  WIND %.0f m/s  AUTO %.0f m  •  X DROP  •  IMPACT %.0f m",
        bomber_payload_label(editor.bomber_payload_kind),
        readiness,
        wind_speed,
        drift_distance,
        distance,
    )
    size := canvas2d.MeasureTextEx(canvas2d.Font{}, label, 14, .7)
    panel := canvas2d.Rectangle{26, center.y - radius - 52, size.x + 28, 34}
    canvas2d.DrawRectangleRounded(panel, .25, 8, {9, 25, 28, 220})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .25, 8, 1, {126, 152, 136, 220})
    canvas2d.DrawTextEx(canvas2d.Font{}, label, {panel.x + 14, panel.y + 9}, 14, .7, sight)

    if tracked := bomber_pip_drop(editor); tracked != nil {
        pip := bomber_pip_layout(f32(width), f32(height))
        pip_width, pip_height := pip.width, pip.height
        pip_x, pip_y := pip.x, pip.y
        border := canvas2d.Rectangle{pip_x - 3, pip_y - 3, pip_width + 6, pip_height + 6}
        canvas2d.DrawRectangleRoundedLinesEx(border, .035, 8, 3, {8, 20, 22, 235})
        canvas2d.DrawRectangleRoundedLinesEx({pip_x - 1, pip_y - 1, pip_width + 2, pip_height + 2}, .035, 8, 1, sight)
        airborne_count := 0
        for drop in editor.bomber_drops[:editor.bomber_drop_count] {
            if !drop.landed do airborne_count += 1
        }
        pip_label := fmt.ctprintf(
            "DROP CAM  %s  •  %.0f m AGL  •  ETA %.1fs  •  %d AIRBORNE",
            bomber_payload_label(tracked.kind),
            max(
                tracked.position.y -
                max(
                    terrain.sample_surface_height(&editor.project, 0, tracked.position.x, tracked.position.z),
                    editor.project.sea_level,
                ),
                f32(0),
            ),
            bomber_drop_eta(editor, tracked),
            airborne_count,
        )
        canvas2d.DrawRectangle(i32(pip_x), i32(pip_y), i32(pip_width), 26, {8, 23, 25, 205})
        canvas2d.DrawTextEx(canvas2d.Font{}, pip_label, {pip_x + 10, pip_y + 7}, 12, .6, sight)
    }
    if editor.bomber_touchdown_flash > 0 {
        touchdown_alpha := u8(clamp(editor.bomber_touchdown_flash * 255, 0, 255))
        touchdown_label := fmt.ctprintf("%s TOUCHDOWN", bomber_payload_label(editor.bomber_touchdown_kind))
        touchdown_size := canvas2d.MeasureTextEx(canvas2d.Font{}, touchdown_label, 15, .7)
        touchdown_panel := canvas2d.Rectangle{f32(width) - touchdown_size.x - 128, 312, touchdown_size.x + 24, 32}
        canvas2d.DrawRectangleRounded(
            touchdown_panel,
            .22,
            8,
            {22, 72, 61, u8(clamp(f32(touchdown_alpha) * .9, 0, 230))},
        )
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            touchdown_label,
            {touchdown_panel.x + 12, touchdown_panel.y + 8},
            15,
            .7,
            {153, 242, 196, touchdown_alpha},
        )
    }
}

draw_flight_instruments :: proc(editor: ^Editor, width, height: i32, altitude: f32) {
    if editor.aircraft.active == .Rondine {
        draw_rondine_instruments(editor, width, height)
        return
    }
    panel_width := min(f32(width) - 32, f32(620))
    panel_height := f32(184)
    panel_left := f32(width) * .5 - panel_width * .5
    panel_top := f32(height) - panel_height - 14
    draw_flight_console_panel(
        {x = panel_left, y = panel_top, width = panel_width, height = panel_height},
        112,
        {r = 10, g = 21, b = 21, a = 246},
    )
    body := active_aircraft_body(editor)
    basis := flight.basis_from_orientation(body.orientation)
    airspeed := active_aircraft_airspeed(editor)
    vertical_speed := body.velocity.y
    bank := postale_game.bank_radians(basis)
    pitch := math.asin(clamp(basis.forward.y, -1, 1))
    heading := postale_game.yaw_radians(basis) * 180 / math.PI
    if heading < 0 do heading += 360
    dial_spacing := panel_width / 3
    dial_radius := clamp(dial_spacing * .30, 54, 64)
    y := panel_top + 68
    draw_instrument_dial(
        {panel_left + dial_spacing * .5, y},
        dial_radius,
        "AIRSPEED",
        airspeed,
        0,
        70,
        fmt.ctprintf("%.0f m/s", airspeed),
        range_start = 24,
        range_end = 70,
    )
    draw_attitude_indicator({panel_left + dial_spacing * 1.5, y}, dial_radius, pitch, bank)
    draw_instrument_dial(
        {panel_left + dial_spacing * 2.5, y},
        dial_radius,
        "ALTITUDE",
        altitude,
        0,
        500,
        fmt.ctprintf("%.0f m", altitude),
        dial_radius * .62,
        reference_value = 250,
    )
    draw_vsi_inset({panel_left + dial_spacing * 2.5, y}, dial_radius, vertical_speed)
    compass_y := panel_top + 151
    draw_heading_compass({f32(width) * .5, compass_y}, 276, heading)
    draw_throttle_overlay(editor, width, height, active_aircraft_throttle(editor))
}

draw_aircraft_speed_effects :: proc(editor: ^Editor, width, height: i32, time: f32) {
    if editor == nil ||
       !editor.in_map ||
       !driving_aircraft(editor) ||
       active_aircraft_grounded(editor) ||
       active_aircraft_crashed(editor) {
        return
    }
    airflow_speed := active_aircraft_apparent_airflow_speed(editor)
    intensity := air_effects.streak_strength(airflow_speed)
    // The speed overlay is composited after the 3D world, so fragment fog
    // cannot attenuate it. Fade it with atmospheric visibility instead of
    // drawing bright radial lanes over a fog-bank interior.
    atmospheric_visibility :=
        1 - clamp(editor.atmosphere.weather.haze * 2.0 + editor.atmosphere.weather.precipitation * 1.5, 0, 1)
    intensity *= atmospheric_visibility
    if intensity <= .001 do return

    body := active_aircraft_body(editor)
    short_side := min(f32(width), f32(height))
    center := canvas2d.Vector2 {
        x = f32(width) * .5,
        y = f32(height) * .46,
    }
    air_forward := third_person.Vec3 {
        body.velocity.x - editor.atmosphere.weather.wind[0],
        body.velocity.y,
        body.velocity.z - editor.atmosphere.weather.wind[1],
    }
    if linalg.length(air_forward) > 1 {
        air_forward = linalg.normalize0(air_forward)
        projected := project_3d(
            perspective_camera(editor.camera_pose, editor.flight_camera.focal_length),
            flight_to_world(body.position) + air_forward * 120,
            width,
            height,
        )
        if projected.visible {
            // Clamp only the pathological edge cases. Normal flight retains
            // the exact air-relative direction, including slip and climb.
            center.x = clamp(projected.position.x, f32(width) * .25, f32(width) * .75)
            center.y = clamp(projected.position.y, f32(height) * .20, f32(height) * .68)
        }
    }
    long_side := max(f32(width), f32(height))
    streak_count := air_effects.screen_streak_count(airflow_speed)
    for index in 0 ..< streak_count {
        seed := f32(index) * 2.399963
        speed_variation := .72 + f32(math.sin(f64(seed * 2.17))) * .18
        // Keep screen-space travel below the point where repeated radial lanes
        // wagon-wheel backward between frames. Length and opacity still grow
        // aggressively with airspeed, while travel itself stays readable.
        cycle := time * (.65 + intensity * .75) * speed_variation + f32(index) * .173
        progress := cycle - f32(math.floor(f64(cycle)))
        eased := progress * progress
        // Keep the radial overlay outside the aircraft silhouette. Since this
        // pass is composited after the 3D scene it cannot use world depth; a
        // generous, varied inner radius preserves the cockpit and wings.
        inner := short_side * (.21 + .10 * (.5 + .5 * f32(math.sin(f64(seed * 1.31)))))
        distance := inner + (long_side * .70 - inner) * eased
        ray_x := f32(math.cos(f64(seed)))
        ray_y := f32(math.sin(f64(seed))) * .64
        variation := math.abs(f32(math.sin(f64(seed * 3.07))))
        streak_length := (10 + intensity * 64) * (.72 + .28 * variation)
        fade := 1 - math.abs(progress * 2 - 1)
        alpha := u8(clamp((24 + intensity * 126) * fade, 0, 144))
        // The leading edge is always the point farthest from the vanishing
        // point. Fade and taper the trail toward its inner end so a streak can
        // never read as moving back toward the aircraft.
        trail_segments :: 4
        for segment in 0 ..< trail_segments {
            inner_amount := f32(segment) / f32(trail_segments)
            outer_amount := f32(segment + 1) / f32(trail_segments)
            start_distance := distance + streak_length * inner_amount
            finish_distance := distance + streak_length * outer_amount
            start := canvas2d.Vector2{center.x + ray_x * start_distance, center.y + ray_y * start_distance}
            finish := canvas2d.Vector2{center.x + ray_x * finish_distance, center.y + ray_y * finish_distance}
            segment_alpha := u8(clamp(f32(alpha) * (.28 + outer_amount * .72), 0, 126))
            segment_width := (.85 + intensity * 1.55) * (.70 + outer_amount * .30)
            // Speed is a warm, screen-space effect radiating from the flight
            // vanishing point. A dim amber body and narrow ivory core read as
            // one luminous streak instead of a flat UI line; wind remains
            // cool and world-aligned.
            body_alpha := u8(clamp(f32(segment_alpha) * .48, 0, 72))
            canvas2d.DrawLineEx(start, finish, segment_width + .9, {205, 174, 108, body_alpha})
            canvas2d.DrawLineEx(start, finish, max(segment_width * .42, f32(.65)), {255, 235, 181, segment_alpha})
        }
        head_distance := distance + streak_length
        head := canvas2d.Vector2{center.x + ray_x * head_distance, center.y + ray_y * head_distance}
        head_alpha := u8(clamp(f32(alpha) * .82, 0, 138))
        canvas2d.DrawCircleV(head, .7 + intensity * .72, {255, 235, 174, head_alpha})
    }

}
