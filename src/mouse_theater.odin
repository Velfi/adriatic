package main

import atmosphere "../packages/atmosphere"
import engine_sound "../packages/engine_sound"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:strings"
import canvas2d "zelda_engine:canvas2d"

// Mouse Theater is a deterministic, transient cinematic stage. Its geometry is
// generated each frame from a compact auditorium plan, leaving future shots
// free to change the cast and blocking without depending on authored assets.

MOUSE_THEATER_ROWS :: 7
MOUSE_THEATER_SEATS_PER_ROW :: 12

Mouse_Theater_Beat :: struct {
    text:          string,
    opening_pause: f32,
    line_pause:    f32,
    final_hold:    f32,
}

MOUSE_THEATER_MONOLOGUE := [?]Mouse_Theater_Beat {
    {"Ora ist el winter de nostro discontent,\nMa il sun de York lo fa estate splendente.", .9, .8, 1.4},
    {"Todas las nuvole sopra nostra casa\nSind nel mare enterradas—ombra rasa.", .55, .9, 1.5},
    {"Jetzt nos frontes portan corone de victoria;\nArmes ferite hängen quiete in memoria.", .7, .85, 1.35},
    {"Les alarmes sévères diventano incontri;\nMarches terribles turn to measures giocondi.", .5, .75, 1.3},
    {"Grim guerra ha lissé son rugoso fronte;\nNiente barded steeds, niente guerra al monte.", .75, 1.0, 1.5},
    {"Pour terroriser almas d'adversari,\nMaintenant il danse entre lumi e scenari.", .55, .8, 1.65},
    {"Au plaisir lascivo del dolce liuto;\nMa io, malformato, non conosco quel saluto.", .8, 1.15, 1.8},
    {"Ni fatto para courtiser miroir amoroso;\nRudely stampato, sans un gesto glorioso.", .65, .9, 1.45},
    {"Non strut davanti une ninfa vagabonda;\nEsta proporzione fu tagliata non rotonda.", .55, .8, 1.4},
    {"Tradito nel viso par falsa natura;\nDeformato, poslan antes—creatura prematura.", .7, 1.2, 1.75},
    {"Dans questo mondo, appena medio fatto;\nCosì boiteux, ganz mal disfatto.", .65, 1.0, 1.65},
    {"Los cani bark quand je passo vicino;\nIn questo debole peace, voilà mon destino.", .75, .95, 1.8},
    {"Non ho plaisir pour passer este tiempo;\nSalvo spy mein ombra nel sole e nel vento.", .65, .9, 1.55},
    {"Et cantar sopra mia deformité;\nCar non puedo devenir lover né aimé.", .7, 1.25, 1.9},
    {"Pour divertir ces jours trop bien parlés,\nSono determinato: villain, sì, mauvais.", .9, 1.35, 2.1},
    {"Ich werde odiar los plaisirs così vains;\nOggi scelgo mal—e villain demain.", .8, 1.4, 2.6},
}

MOUSE_THEATER_VOICE :: engine_sound.Dialogue_Voice_Profile {
    base_hz    = 345,
    range_hz   = 145,
    brightness = .54,
    warmth     = .68,
    gain       = .105,
    tract_hz   = 345,
}

Mouse_Theater_Dialogue :: struct {
    beat:             int,
    cursor:           int,
    reveal_timer:     f32,
    beat_time:        f32,
    performance_time: f32,
    last_time:        f64,
    complete:         bool,
}

mouse_theater_dialogue: Mouse_Theater_Dialogue

mouse_theater_text_seconds :: proc(text: string) -> f32 {
    seconds := f32(0)
    cursor := 0
    for cursor < len(text) {
        start := cursor
        cursor = dialogue_voice_unit_end(text, start)
        seconds += DIALOGUE_REVEAL_SECONDS + dialogue_reveal_pause(text[start:cursor])
    }
    return seconds
}

mouse_theater_beat_seconds :: proc(beat: Mouse_Theater_Beat) -> f32 {
    // Each rendered phrase gets a short voice-release tail. The newline is
    // presentation only; its authored pause is shared by picture and sound.
    split := strings.index_byte(beat.text, '\n')
    if split < 0 {
        return beat.opening_pause + mouse_theater_text_seconds(beat.text) + .24 + beat.final_hold
    }
    return(
        beat.opening_pause +
        mouse_theater_text_seconds(beat.text[:split]) +
        .24 +
        beat.line_pause +
        mouse_theater_text_seconds(beat.text[split + 1:]) +
        .24 +
        beat.final_hold \
    )
}

mouse_theater_append_silence :: proc(samples: ^[dynamic]f32, seconds: f32) {
    if samples == nil || seconds <= 0 do return
    append(samples, ..make([]f32, int(seconds * engine_sound.SAMPLE_RATE), context.temp_allocator))
}

mouse_theater_export_audio :: proc(path: string) -> (f32, bool) {
    samples := make([dynamic]f32, 0, 4096, context.allocator)
    defer delete(samples)
    for beat in MOUSE_THEATER_MONOLOGUE {
        mouse_theater_append_silence(&samples, beat.opening_pause)
        split := strings.index_byte(beat.text, '\n')
        phrase_count := split >= 0 ? 2 : 1
        for phrase_index in 0 ..< phrase_count {
            phrase := beat.text
            if split >= 0 {
                phrase = phrase_index == 0 ? beat.text[:split] : beat.text[split + 1:]
            }
            rendered := dialogue_voice_preview_render(
                phrase,
                MOUSE_THEATER_VOICE,
                unit_blend = .82,
                expression = .86,
                allocator = context.allocator,
            )
            append(&samples, ..rendered[:])
            delete(rendered)
            if phrase_index == 0 && phrase_count == 2 {
                mouse_theater_append_silence(&samples, beat.line_pause)
            }
        }
        mouse_theater_append_silence(&samples, beat.final_hold)
    }
    if len(samples) == 0 || !dialogue_voice_preview_write_wav(path, samples[:]) do return 0, false
    return f32(len(samples)) / engine_sound.SAMPLE_RATE, true
}

mouse_theater_export_set_time :: proc(seconds: f32) {
    remaining := max(seconds, 0)
    for authored, beat in MOUSE_THEATER_MONOLOGUE {
        duration := mouse_theater_beat_seconds(authored)
        if remaining >= duration {
            remaining -= duration
            continue
        }
        mouse_theater_dialogue.beat = beat
        mouse_theater_dialogue.complete = false
        mouse_theater_dialogue.reveal_timer = 0
        mouse_theater_dialogue.cursor = 0
        mouse_theater_dialogue.beat_time = remaining
        mouse_theater_dialogue.performance_time = seconds
        text := authored.text
        if remaining < authored.opening_pause do return
        remaining -= authored.opening_pause
        elapsed := f32(0)
        for mouse_theater_dialogue.cursor < len(text) {
            start := mouse_theater_dialogue.cursor
            next := dialogue_voice_unit_end(text, start)
            unit := text[start:next]
            unit_seconds := DIALOGUE_REVEAL_SECONDS + dialogue_reveal_pause(unit)
            if unit == "\n" do unit_seconds = .24 + authored.line_pause
            if elapsed + unit_seconds > remaining do break
            mouse_theater_dialogue.cursor = next
            elapsed += unit_seconds
        }
        return
    }
    mouse_theater_dialogue.complete = true
    mouse_theater_dialogue.beat = len(MOUSE_THEATER_MONOLOGUE)
    mouse_theater_dialogue.cursor = 0
    mouse_theater_dialogue.performance_time = seconds
}

mouse_theater_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil || target != "" do return false
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.project.sea_level = -20
    for &level in editor.project.levels {
        for &height in level.heights do height = 0
    }

    // The enclosure supplies most of the darkness. A trace of blue-hour
    // ambience preserves silhouettes in the lowered house lights.
    atmosphere.set_world_minutes(&editor.atmosphere, 21 * 60)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    mouse_theater_dialogue = {
        reveal_timer = MOUSE_THEATER_MONOLOGUE[0].opening_pause,
        last_time    = canvas2d.GetTime(),
    }
    engine_sound.dialogue_voice_stop(&editor.engine_audio)
    editor.engine_audio.dialogue_voice.unit_blend = .82

    set_pointer_locked(false)
    editor.camera_pose = third_person.camera_look_at({5.4, 3.35, 5.9}, {0, .95, -2.0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    mouse_theater_camera_update(editor)
    return true
}

mouse_theater_exit :: proc(editor: ^Editor) {
    if editor != nil {
        engine_sound.dialogue_voice_stop(&editor.engine_audio)
        editor.cinematic_focal_length = 1.35
    }
    mouse_theater_dialogue = {}
}

mouse_theater_current_text :: proc() -> string {
    if mouse_theater_dialogue.complete ||
       mouse_theater_dialogue.beat < 0 ||
       mouse_theater_dialogue.beat >= len(MOUSE_THEATER_MONOLOGUE) {
        return ""
    }
    return MOUSE_THEATER_MONOLOGUE[mouse_theater_dialogue.beat].text
}

mouse_theater_dialogue_tick :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || mouse_theater_dialogue.complete do return
    mouse_theater_dialogue.beat_time += max(delta_seconds, 0)
    mouse_theater_dialogue.performance_time += max(delta_seconds, 0)
    text := mouse_theater_current_text()
    mouse_theater_dialogue.reveal_timer -= max(delta_seconds, 0)
    for mouse_theater_dialogue.cursor < len(text) && mouse_theater_dialogue.reveal_timer <= 0 {
        start := mouse_theater_dialogue.cursor
        mouse_theater_dialogue.cursor = dialogue_voice_unit_end(text, start)
        unit := text[start:mouse_theater_dialogue.cursor]
        if unit == "\n" {
            mouse_theater_dialogue.reveal_timer +=
                .24 + MOUSE_THEATER_MONOLOGUE[mouse_theater_dialogue.beat].line_pause
        } else {
            mouse_theater_dialogue.reveal_timer += DIALOGUE_REVEAL_SECONDS + dialogue_reveal_pause(unit)
        }
        if dialogue_voice_should_synthesize_at(text, start, mouse_theater_dialogue.cursor) {
            engine_sound.dialogue_voice_trigger_grapheme(
                &editor.engine_audio,
                unit,
                MOUSE_THEATER_VOICE,
                dialogue_voice_cadence_hint(text, start, mouse_theater_dialogue.cursor),
                dialogue_voice_next_synthesized_grapheme(text, mouse_theater_dialogue.cursor),
                dialogue_voice_word_progress(text, start, mouse_theater_dialogue.cursor),
                .86,
            )
        } else if unit == " " || unit == "\t" {
            engine_sound.dialogue_voice_mixer_word_boundary(&editor.engine_audio.dialogue_voice)
        } else if dialogue_voice_is_phrase_boundary(unit) {
            engine_sound.dialogue_voice_phrase_boundary(&editor.engine_audio)
        }
    }
}

mouse_theater_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    if cinematic_export_active {
        mouse_theater_export_set_time(cinematic_export_time)
        mouse_theater_camera_update(editor)
        return
    }
    now := canvas2d.GetTime()
    delta := f32(clamp(now - mouse_theater_dialogue.last_time, f64(0), f64(.05)))
    mouse_theater_dialogue.last_time = now
    mouse_theater_dialogue_tick(editor, delta)
    mouse_theater_camera_update(editor)

    advance :=
        input_action_pressed(.Menu_Accept) || canvas2d.IsKeyPressed(.SPACE) || canvas2d.IsMouseButtonPressed(.LEFT)
    if !advance || mouse_theater_dialogue.complete do return
    text := mouse_theater_current_text()
    if mouse_theater_dialogue.cursor < len(text) {
        mouse_theater_dialogue.cursor = len(text)
        mouse_theater_dialogue.reveal_timer = 0
        engine_sound.dialogue_voice_stop(&editor.engine_audio)
        return
    }
    mouse_theater_dialogue.beat += 1
    mouse_theater_dialogue.cursor = 0
    mouse_theater_dialogue.beat_time = 0
    if mouse_theater_dialogue.beat < len(MOUSE_THEATER_MONOLOGUE) {
        mouse_theater_dialogue.reveal_timer = MOUSE_THEATER_MONOLOGUE[mouse_theater_dialogue.beat].opening_pause
    } else {
        mouse_theater_dialogue.reveal_timer = 0
    }
    engine_sound.dialogue_voice_stop(&editor.engine_audio)
    if mouse_theater_dialogue.beat >= len(MOUSE_THEATER_MONOLOGUE) {
        mouse_theater_dialogue.complete = true
    }
}

mouse_theater_draw_ui :: proc(_: ^Editor, width, height: i32) {
    if mouse_theater_dialogue.complete do return
    text := mouse_theater_current_text()
    visible := text[:min(mouse_theater_dialogue.cursor, len(text))]
    scale := max(f32(height) / 720, f32(1))
    margin := max(f32(width) * .075, 54 * scale)
    panel_h := 154 * scale
    panel := canvas2d.Rectangle {
        x      = margin,
        y      = f32(height) - panel_h - 26 * scale,
        width  = f32(width) - margin * 2,
        height = panel_h,
    }
    gold: canvas2d.Color = {232, 191, 91, 255}
    pale_gold: canvas2d.Color = {255, 224, 142, 255}
    shadow: canvas2d.Color = {20, 10, 4, 245}
    canvas2d.DrawRectangleRounded(panel, .08, 10, {8, 5, 5, 218})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .08, 10, 2 * scale, {151, 104, 36, 255})
    canvas2d.DrawRectangleRoundedLinesEx(
        {panel.x + 5 * scale, panel.y + 5 * scale, panel.width - 10 * scale, panel.height - 10 * scale},
        .07,
        10,
        1 * scale,
        {82, 53, 20, 255},
    )

    quote_size := 48 * scale
    canvas2d.DrawTextEx(
        canvas2d.DisplayFont(),
        "“",
        {panel.x + 20 * scale, panel.y + 14 * scale},
        quote_size,
        1,
        gold,
    )
    canvas2d.DrawTextEx(
        canvas2d.DisplayFont(),
        "”",
        {panel.x + panel.width - 48 * scale, panel.y + panel.height - 66 * scale},
        quote_size,
        1,
        gold,
    )
    bounds := canvas2d.Rectangle {
        panel.x + 70 * scale,
        panel.y + 25 * scale,
        panel.width - 140 * scale,
        panel.height - 55 * scale,
    }
    font_size := 25 * scale
    line_height := 34 * scale
    canvas2d.DrawTextWrappedEx(
        canvas2d.DisplayFont(),
        fmt.ctprintf("%s", visible),
        {bounds.x + 2 * scale, bounds.y + 2 * scale, bounds.width, bounds.height},
        font_size,
        1.1 * scale,
        line_height,
        shadow,
    )
    canvas2d.DrawTextWrappedEx(
        canvas2d.DisplayFont(),
        fmt.ctprintf("%s", visible),
        bounds,
        font_size,
        1.1 * scale,
        line_height,
        pale_gold,
    )
    prompt: cstring = mouse_theater_dialogue.cursor < len(text) ? "ADVANCE TO REVEAL" : "ADVANCE"
    prompt_size := canvas2d.MeasureTextEx(canvas2d.DisplayFont(), prompt, 10 * scale, 1)
    canvas2d.DrawTextEx(
        canvas2d.DisplayFont(),
        prompt,
        {panel.x + panel.width - prompt_size.x - 24 * scale, panel.y + panel.height - 20 * scale},
        10 * scale,
        1,
        {174, 133, 61, 255},
    )
}

mouse_theater_seat :: proc(center: third_person.Vec3) {
    upholstery: canvas2d.Color = {43, 12, 18, 255}
    upholstery_edge: canvas2d.Color = {68, 20, 27, 255}
    wood: canvas2d.Color = {43, 29, 24, 255}
    world_box(center, {.72, .16, .68}, upholstery)
    world_box({center.x, center.y + .48, center.z + .28}, {.76, .86, .14}, upholstery_edge)
    world_box({center.x - .34, center.y - .28, center.z}, {.08, .58, .08}, wood)
    world_box({center.x + .34, center.y - .28, center.z}, {.08, .58, .08}, wood)
}

world_mouse_theater_auditorium :: proc() {
    near_black: canvas2d.Color = {8, 7, 10, 255}
    wall: canvas2d.Color = {18, 13, 18, 255}
    aisle: canvas2d.Color = {31, 20, 22, 255}
    brass: canvas2d.Color = {115, 79, 35, 255}

    // A shallow proscenium and closed black-box shell keep the first shot
    // intimate while still reading immediately as a theater.
    world_box({0, -.22, 1.5}, {24, .42, 29}, near_black)
    world_box({0, 6.5, -7.2}, {24, 13, .45}, wall)
    world_box({-11.8, 6.5, 1.5}, {.45, 13, 29}, wall)
    world_box({11.8, 6.5, 1.5}, {.45, 13, 29}, wall)
    world_box({0, 12.8, 1.5}, {24, .4, 29}, near_black)

    // Raised stage, apron, and red velvet around the playing space.
    world_box({0, .24, -3.55}, {14.5, .48, 6.8}, {38, 30, 27, 255})
    world_box({0, .50, -.18}, {15.2, .22, .36}, brass)
    // A full house curtain gives the opening shot a readable theatrical
    // backdrop. Alternating shallow folds keep the velvet from becoming a
    // single flat maroon wall in the lowered light.
    for fold in 0 ..< 18 {
        x := -6.38 + f32(fold) * .75
        fold_color := fold % 2 == 0 ? canvas2d.Color{91, 10, 22, 255} : canvas2d.Color{61, 7, 17, 255}
        depth := fold % 2 == 0 ? f32(.28) : f32(.18)
        fold_first := len(world_renderer.vertices)
        world_box_rotated_material({x, 5.05, -6.56 + depth * .5}, {.79, 9.65, depth}, 0, fold_color, .BRDF)
        for &vertex in world_renderer.vertices[fold_first:] do vertex.material = {0, .92}
    }
    world_box({-6.75, 5.1, -6.75}, {1.45, 9.8, .48}, {57, 8, 16, 255})
    world_box({6.75, 5.1, -6.75}, {1.45, 9.8, .48}, {57, 8, 16, 255})
    world_box({0, 10.05, -6.75}, {14.9, .58, .55}, {73, 10, 19, 255})

    // Raked rows are generated symmetrically around a center aisle.
    for row in 0 ..< MOUSE_THEATER_ROWS {
        row_f := f32(row)
        z := 2.0 + row_f * 1.42
        y := .44 + row_f * .24
        world_box({0, y - .40, z}, {20.5, .38, 1.35}, aisle)
        for seat in 0 ..< MOUSE_THEATER_SEATS_PER_ROW {
            side := seat < MOUSE_THEATER_SEATS_PER_ROW / 2 ? f32(-1) : f32(1)
            local := seat % (MOUSE_THEATER_SEATS_PER_ROW / 2)
            x := side * (1.15 + f32(local) * 1.42)
            // A small deterministic stagger breaks the rigid grid without
            // introducing mutable scene state.
            x += math.sin(f32(row * 17 + seat * 11)) * .055
            mouse_theater_seat({x, y, z})
        }
    }
}

world_mouse_theater_limelights :: proc(editor: ^Editor) {
    housing: canvas2d.Color = {29, 31, 27, 255}
    lime_glass: canvas2d.Color = {205, 255, 174, 255}
    for lamp in 0 ..< 9 {
        x := -5.2 + f32(lamp) * 1.30
        // Traditional footlight placement along the apron, with compact
        // green-white sources that lift the curtain hem and the actor's lower
        // silhouette without flattening the overhead key.
        world_box_rotated({x, .73, -.02}, {.52, .28, .36}, 0, housing)
        world_box_rotated_material({x, .86, -.11}, {.34, .10, .16}, 0, lime_glass, .Emissive)
        world_billboard_material_uv(editor, {x, .91, -.18}, .58, .42, {190, 255, 158, 92}, .Emissive_Halo, true)
    }
}

world_mouse_theater_spotlight :: proc(editor: ^Editor) {
    warm: canvas2d.Color = {255, 220, 157, 255}
    rig: canvas2d.Color = {35, 35, 39, 255}
    // Visible source and yoke establish where the pool comes from. The
    // emissive material provides a soft-edged spotlight footprint at night.
    world_tube_between({0, 12.55, -2.47}, {0, 11.75, -2.18}, {1, 0, 0}, .34, .42, rig)
    world_tube_between({0, 11.80, -2.18}, {0, 11.52, -2.0}, {1, 0, 0}, .30, .24, warm)
    world_municipal_light_pool(0, .50, -2.0, nil, .04, 2.75, 2.15, 0, 205, 0, warm, nil, true)
}

MOUSE_THEATER_STAGE_X := [?]f32{0, -.65, -1.2, -.45, .45, 1.15, .55, -.25, -.95, -1.35, -.55, .35, 1.1, .65, -.2, 0}

MOUSE_THEATER_STAGE_Z := [?]f32 {
    -2.0,
    -2.08,
    -2.18,
    -2.05,
    -2.12,
    -2.22,
    -1.92,
    -1.82,
    -2.05,
    -2.22,
    -1.95,
    -1.78,
    -2.08,
    -1.86,
    -1.68,
    -1.48,
}

Mouse_Theater_Shot :: struct {
    eye_start, eye_end:     third_person.Vec3,
    target_height:          f32,
    focal_start, focal_end: f32,
}

MOUSE_THEATER_SHOTS := [?]Mouse_Theater_Shot {
    {{5.4, 3.35, 5.9}, {4.8, 3.05, 5.1}, .96, 1.20, 1.30}, // house master; slow settle
    {{-4.2, 2.25, 3.2}, {-3.7, 2.10, 2.6}, .88, 1.36, 1.46}, // cut: house left
    {{3.9, 2.05, 2.7}, {3.35, 1.90, 2.15}, .86, 1.42, 1.52}, // cut: house right
    {{-.8, 1.55, 2.55}, {-.65, 1.48, 2.15}, .83, 1.48, 1.58}, // centered medium
    {{-4.1, 1.55, -.75}, {-3.55, 1.47, -.72}, .80, 1.50, 1.62}, // hard profile
    {{3.7, 1.48, -.55}, {3.15, 1.40, -.58}, .80, 1.54, 1.66}, // reverse profile
    {{1.8, 1.50, 1.10}, {1.45, 1.38, .65}, .79, 1.58, 1.74}, // dolly to confession
    {{-2.0, 1.42, .75}, {-1.55, 1.34, .38}, .78, 1.62, 1.76}, // opposing close
    {{4.3, 2.15, 3.4}, {3.8, 1.90, 2.55}, .86, 1.38, 1.52}, // release to medium
    {{-3.6, 1.58, -.35}, {-3.05, 1.42, -.42}, .80, 1.55, 1.70}, // deformity profile
    {{2.7, 1.55, .45}, {2.15, 1.38, .12}, .78, 1.58, 1.74}, // reverse close
    {{-1.55, 1.34, .10}, {-1.25, 1.25, -.12}, .76, 1.66, 1.82}, // dogs: intimate
    {{3.5, 2.10, 2.7}, {2.9, 1.78, 1.85}, .83, 1.44, 1.62}, // shadow: breathe out
    {{-1.55, 1.28, -.05}, {-1.12, 1.20, -.32}, .74, 1.72, 1.88}, // lover: close
    {{1.20, 1.24, -.02}, {.78, 1.14, -.58}, .72, 1.78, 2.02}, // villain: push
    {{0, 1.18, .15}, {0, 1.02, -1.05}, .68, 1.86, 2.22}, // final dead-on zoom
}

mouse_theater_actor_pose :: proc() -> (position: third_person.Vec3, rotation, gait_speed, gait_phase: f32) {
    beat := clamp(mouse_theater_dialogue.beat, 0, len(MOUSE_THEATER_STAGE_X) - 1)
    previous := max(beat - 1, 0)
    // The actor crosses during the opening breath and first words, then plants
    // his feet so the important line breaks read as deliberate stillness.
    travel_seconds := MOUSE_THEATER_MONOLOGUE[beat].opening_pause + .9
    raw_travel := clamp(mouse_theater_dialogue.beat_time / max(travel_seconds, .1), 0, 1)
    travel := raw_travel * raw_travel * (3 - 2 * raw_travel)
    delta_x := MOUSE_THEATER_STAGE_X[beat] - MOUSE_THEATER_STAGE_X[previous]
    delta_z := MOUSE_THEATER_STAGE_Z[beat] - MOUSE_THEATER_STAGE_Z[previous]
    travel_distance := f32(math.sqrt(f64(delta_x * delta_x + delta_z * delta_z)))
    x := MOUSE_THEATER_STAGE_X[previous] + delta_x * travel
    z := MOUSE_THEATER_STAGE_Z[previous] + delta_z * travel
    moving := travel < .995 && beat > 0

    text := mouse_theater_current_text()
    split := strings.index_byte(text, '\n')
    second_line := split >= 0 && mouse_theater_dialogue.cursor > split
    // A slight quarter-turn addresses first one side of the house, then the
    // other. The final two beats square up and advance toward the audience.
    address := beat % 2 == 0 ? f32(-.13) : f32(.13)
    if second_line do address = -address
    if beat >= len(MOUSE_THEATER_MONOLOGUE) - 2 do address *= .35

    // Face along the cross while the paws are moving, then pivot toward the
    // house as the actor plants. This avoids asking a forward gait to imitate
    // ultra-slow strafing.
    rotation = address
    if moving && travel_distance > .001 {
        path_rotation := math.atan2(-delta_x, delta_z)
        face_house := clamp((travel - .72) / .28, 0, 1)
        face_house = face_house * face_house * (3 - 2 * face_house)
        rotation = path_rotation + (address - path_rotation) * face_house
    }

    // Derive cadence from actual path velocity and phase from distance. Paws
    // now slow continuously into their plant instead of cycling on a timer.
    gait_speed = 0
    if moving {
        gait_speed = travel_distance * 6 * raw_travel * (1 - raw_travel) / max(travel_seconds, f32(.1))
    }
    distance_traveled := travel_distance * travel
    for transition in 1 ..< beat {
        step_x := MOUSE_THEATER_STAGE_X[transition] - MOUSE_THEATER_STAGE_X[transition - 1]
        step_z := MOUSE_THEATER_STAGE_Z[transition] - MOUSE_THEATER_STAGE_Z[transition - 1]
        distance_traveled += f32(math.sqrt(f64(step_x * step_x + step_z * step_z)))
    }
    gait_phase = distance_traveled / 1.55 * 6.0

    return third_person.Vec3{x, .50, z}, rotation, gait_speed, gait_phase
}

mouse_theater_camera_update :: proc(editor: ^Editor) {
    if editor == nil do return
    beat := clamp(mouse_theater_dialogue.beat, 0, len(MOUSE_THEATER_SHOTS) - 1)
    shot := MOUSE_THEATER_SHOTS[beat]
    duration := mouse_theater_beat_seconds(MOUSE_THEATER_MONOLOGUE[beat])
    progress := clamp(mouse_theater_dialogue.beat_time / max(duration, .1), 0, 1)
    progress = progress * progress * (3 - 2 * progress)
    eye := third_person.Vec3 {
        shot.eye_start.x + (shot.eye_end.x - shot.eye_start.x) * progress,
        shot.eye_start.y + (shot.eye_end.y - shot.eye_start.y) * progress,
        shot.eye_start.z + (shot.eye_end.z - shot.eye_start.z) * progress,
    }
    actor_position, _, _, _ := mouse_theater_actor_pose()
    target := third_person.Vec3{actor_position.x, shot.target_height, actor_position.z}
    editor.cinematic_focal_length = shot.focal_start + (shot.focal_end - shot.focal_start) * progress
    editor.camera_pose = third_person.camera_look_at(eye, target)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

world_mouse_theater :: proc(editor: ^Editor) {
    if editor == nil do return
    world_mouse_theater_auditorium()
    world_mouse_theater_limelights(editor)
    world_mouse_theater_spotlight(editor)
    actor_position, actor_rotation, actor_gait_speed, actor_gait_phase := mouse_theater_actor_pose()
    world_mouse_model_scaled(
        editor,
        {
            position = actor_position,
            rotation = actor_rotation,
            fur = .Chestnut,
            pattern = .Solid,
            grounded = false,
            gait_preview = true,
            gait_speed = actor_gait_speed,
            gait_phase = actor_gait_phase,
        },
        1.55,
    )
}
