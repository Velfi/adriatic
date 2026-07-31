package main

import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

// Screen pops are short-lived, screen-space words. A call to screen_pops_say
// splits a message into particles, emits copies from all four screen edges,
// and lets their expanding text bounds push one another apart before popping.

SCREEN_POP_CAP :: 128
SCREEN_POP_TEXT_CAP :: 48
SCREEN_POP_BURST_TIME :: f32(.28)
SCREEN_POP_ATLAS_COLUMNS :: 3
SCREEN_POP_ATLAS_ROWS :: 3
SCREEN_POP_ATLAS_PATH :: "assets/textures/ui/screen-pops-atlas.png"

Screen_Pop_Edge :: enum u8 {
    Left,
    Right,
    Top,
    Bottom,
}

Screen_Pop_Sprite :: enum u8 {
    None,
    Nice,
    Lucky,
    Delivered,
    Special,
    Unlucky,
    Creepy,
    Questions,
    Wtf,
    Sparkles,
}

Screen_Pop_Style :: struct {
    color:       canvas2d.Color,
    accent:      canvas2d.Color,
    lifetime:    f32,
    start_scale: f32,
    end_scale:   f32,
    speed:       f32,
    push:        f32,
}

SCREEN_POP_DEFAULT_STYLE :: Screen_Pop_Style {
    color       = {255, 241, 196, 255},
    accent      = {255, 116, 91, 255},
    lifetime    = 3.05,
    start_scale = .55,
    end_scale   = 3.15,
    speed       = 148,
    push        = 7.5,
}

Screen_Pop_Particle :: struct {
    text:        [SCREEN_POP_TEXT_CAP]u8,
    position:    canvas2d.Vector2,
    velocity:    canvas2d.Vector2,
    age:         f32,
    lifetime:    f32,
    scale:       f32,
    start_scale: f32,
    end_scale:   f32,
    color:       canvas2d.Color,
    accent:      canvas2d.Color,
    push:        f32,
    edge:        Screen_Pop_Edge,
    seed:        u32,
    sprite:      Screen_Pop_Sprite,
    active:      bool,
    bursting:    bool,
}

Screen_Pop_System :: struct {
    particles: [SCREEN_POP_CAP]Screen_Pop_Particle,
    atlas:     canvas2d.Texture,
    cursor:    int,
    rng:       u32,
    last_time: f64,
}

screen_pop_default_style :: proc() -> Screen_Pop_Style {
    return SCREEN_POP_DEFAULT_STYLE
}

screen_pops_reset :: proc(system: ^Screen_Pop_System, seed: u32 = 0x50_0F_F5) {
    if system == nil do return
    atlas := system.atlas
    system^ = {}
    system.atlas = atlas
    system.rng = seed
}

screen_pops_load_atlas :: proc(system: ^Screen_Pop_System, path: string = SCREEN_POP_ATLAS_PATH) -> bool {
    if system == nil do return false
    if system.atlas.ready do return true
    system.atlas = canvas2d.LoadTexture(path)
    return system.atlas.ready
}

screen_pop_random :: proc(system: ^Screen_Pop_System) -> f32 {
    system.rng ~= system.rng << 13
    system.rng ~= system.rng >> 17
    system.rng ~= system.rng << 5
    return f32(system.rng & 0xffff) / 65535
}

screen_pop_copy_text :: proc(destination: []u8, text: string) {
    if len(destination) == 0 do return
    count := min(len(text), len(destination) - 1)
    copy(destination[:count], transmute([]u8)text[:count])
    destination[count] = 0
}

screen_pop_spawn_word :: proc(
    system: ^Screen_Pop_System,
    word: string,
    ordinal: int,
    width, height: i32,
    style: Screen_Pop_Style,
) {
    if system == nil || len(word) == 0 do return
    index := system.cursor % SCREEN_POP_CAP
    system.cursor += 1
    particle := &system.particles[index]
    particle^ = {}
    screen_pop_copy_text(particle.text[:], word)
    particle.edge = Screen_Pop_Edge(ordinal % 4)
    particle.seed = system.rng
    particle.lifetime = max(style.lifetime * (.86 + screen_pop_random(system) * .28), .25)
    particle.start_scale = max(style.start_scale, .1)
    particle.end_scale = max(style.end_scale, particle.start_scale)
    particle.scale = particle.start_scale
    particle.color = style.color
    particle.accent = style.accent
    particle.push = style.push
    particle.active = true

    w, h := f32(width), f32(height)
    inset := f32(18)
    along := .32 + screen_pop_random(system) * .36
    tangent := (screen_pop_random(system) - .5) * style.speed * .38
    speed := style.speed * (.78 + screen_pop_random(system) * .42)
    switch particle.edge {
    case .Left:
        particle.position = {-inset, h * along}
        particle.velocity = {speed, tangent}
    case .Right:
        particle.position = {w + inset, h * along}
        particle.velocity = {-speed, tangent}
    case .Top:
        particle.position = {w * along, -inset}
        particle.velocity = {tangent, speed}
    case .Bottom:
        particle.position = {w * along, h + inset}
        particle.velocity = {tangent, -speed}
    }
}

screen_pops_say :: proc(
    system: ^Screen_Pop_System,
    message: string,
    width, height: i32,
    copies: int = 2,
    style: Screen_Pop_Style = SCREEN_POP_DEFAULT_STYLE,
) {
    if system == nil || len(message) == 0 do return
    word_index := 0
    start := 0
    for cursor in 0 ..= len(message) {
        at_end := cursor == len(message)
        separator := !at_end && (message[cursor] == ' ' || message[cursor] == '\n' || message[cursor] == '\t')
        if !at_end && !separator do continue
        if cursor > start {
            word := message[start:cursor]
            for copy_index in 0 ..< max(copies, 1) {
                screen_pop_spawn_word(system, word, word_index + copy_index, width, height, style)
            }
            word_index += max(copies, 1)
        }
        start = cursor + 1
    }
}

screen_pop_sprite_name :: proc(sprite: Screen_Pop_Sprite) -> string {
    switch sprite {
    case .Nice:
        return "NICE"
    case .Lucky:
        return "LUCKY"
    case .Delivered:
        return "DELIVERED"
    case .Special:
        return "SPECIAL"
    case .Unlucky:
        return "UNLUCKY"
    case .Creepy:
        return "CREEPY"
    case .Questions:
        return "QUESTIONS"
    case .Wtf:
        return "WTF"
    case .Sparkles:
        return "SPARKLES"
    case .None:
    }
    return ""
}

screen_pops_spawn_sprite :: proc(
    system: ^Screen_Pop_System,
    sprite: Screen_Pop_Sprite,
    width, height: i32,
    copies: int = 1,
    style: Screen_Pop_Style = SCREEN_POP_DEFAULT_STYLE,
) {
    if system == nil || sprite == .None || sprite == .Sparkles do return
    if !system.atlas.ready do _ = screen_pops_load_atlas(system)
    for _ in 0 ..< max(copies, 1) {
        index := system.cursor % SCREEN_POP_CAP
        screen_pop_spawn_word(system, screen_pop_sprite_name(sprite), system.cursor, width, height, style)
        system.particles[index].sprite = sprite
    }
}

screen_pop_smoothstep :: proc(value: f32) -> f32 {
    t := math.clamp(value, f32(0), f32(1))
    return t * t * (3 - 2 * t)
}

screen_pop_bounds :: proc(particle: ^Screen_Pop_Particle) -> canvas2d.Rectangle {
    if particle.sprite != .None {
        size := 104 * particle.scale
        return {particle.position.x - size * .5, particle.position.y - size * .5, size, size}
    }
    font_size := 20 * particle.scale
    size := canvas2d.MeasureTextEx(canvas2d.Font{}, cstring(&particle.text[0]), font_size, particle.scale)
    padding := 5 * particle.scale
    return {
        particle.position.x - size.x * .5 - padding,
        particle.position.y - size.y * .5 - padding,
        size.x + padding * 2,
        size.y + padding * 2,
    }
}

screen_pop_atlas_source :: proc(texture: canvas2d.Texture, sprite: Screen_Pop_Sprite) -> canvas2d.Rectangle {
    atlas_index := int(sprite) - 1
    if sprite == .Sparkles do atlas_index = 8
    tile_width := f32(texture.width) / SCREEN_POP_ATLAS_COLUMNS
    tile_height := f32(texture.height) / SCREEN_POP_ATLAS_ROWS
    column := atlas_index % SCREEN_POP_ATLAS_COLUMNS
    row_from_top := atlas_index / SCREEN_POP_ATLAS_COLUMNS
    // Canvas texture coordinates start at the bottom, while the generated
    // atlas is authored row-by-row from the top.
    row := SCREEN_POP_ATLAS_ROWS - row_from_top - 1
    return {f32(column) * tile_width, f32(row) * tile_height, tile_width, tile_height}
}

screen_pops_collide :: proc(system: ^Screen_Pop_System, dt: f32) {
    for i in 0 ..< SCREEN_POP_CAP {
        a := &system.particles[i]
        if !a.active || a.bursting do continue
        a_bounds := screen_pop_bounds(a)
        for j in i + 1 ..< SCREEN_POP_CAP {
            b := &system.particles[j]
            if !b.active || b.bursting do continue
            b_bounds := screen_pop_bounds(b)
            overlap_x := min(a_bounds.x + a_bounds.width, b_bounds.x + b_bounds.width) - max(a_bounds.x, b_bounds.x)
            overlap_y := min(a_bounds.y + a_bounds.height, b_bounds.y + b_bounds.height) - max(a_bounds.y, b_bounds.y)
            if overlap_x <= 0 || overlap_y <= 0 do continue

            delta := canvas2d.Vector2{b.position.x - a.position.x, b.position.y - a.position.y}
            distance := math.sqrt(delta.x * delta.x + delta.y * delta.y)
            if distance < .01 {
                angle := f32((a.seed ~ b.seed) & 255) / 255 * math.TAU
                delta = {math.cos(angle), math.sin(angle)}
                distance = 1
            }
            normal := canvas2d.Vector2{delta.x / distance, delta.y / distance}
            pressure := min(overlap_x, overlap_y) * (a.push + b.push) * .5 * dt
            a.velocity.x -= normal.x * pressure
            a.velocity.y -= normal.y * pressure
            b.velocity.x += normal.x * pressure
            b.velocity.y += normal.y * pressure
        }
    }
}

screen_pops_update :: proc(system: ^Screen_Pop_System, width, height: i32, dt: f32) {
    if system == nil do return
    step := math.clamp(dt, f32(0), f32(.05))
    screen_pops_collide(system, step)
    center := canvas2d.Vector2{f32(width) * .5, f32(height) * .5}
    for &particle in system.particles {
        if !particle.active do continue
        particle.age += step
        if particle.bursting {
            if particle.age >= SCREEN_POP_BURST_TIME do particle.active = false
            continue
        }

        progress := math.clamp(particle.age / particle.lifetime, f32(0), f32(1))
        growth := screen_pop_smoothstep(progress)
        particle.scale = particle.start_scale + (particle.end_scale - particle.start_scale) * growth
        toward_center := canvas2d.Vector2{center.x - particle.position.x, center.y - particle.position.y}
        particle.velocity.x += toward_center.x * step * .34
        particle.velocity.y += toward_center.y * step * .34
        damping := math.pow(f32(.58), step)
        particle.velocity.x *= damping
        particle.velocity.y *= damping
        particle.position.x += particle.velocity.x * step
        particle.position.y += particle.velocity.y * step

        margin := f32(12)
        particle.position.x = math.clamp(particle.position.x, margin, f32(width) - margin)
        particle.position.y = math.clamp(particle.position.y, margin, f32(height) - margin)
        if particle.age >= particle.lifetime {
            particle.bursting = true
            particle.age = 0
        }
    }
}

screen_pop_with_alpha :: proc(color: canvas2d.Color, alpha: f32) -> canvas2d.Color {
    result := color
    result.a = u8(math.clamp(alpha, f32(0), f32(1)) * 255)
    return result
}

screen_pops_draw :: proc(system: ^Screen_Pop_System) {
    if system == nil do return
    for &particle in system.particles {
        if !particle.active do continue
        if particle.bursting {
            t := math.clamp(particle.age / SCREEN_POP_BURST_TIME, f32(0), f32(1))
            radius := 12 + 58 * screen_pop_smoothstep(t)
            color := screen_pop_with_alpha(particle.accent, 1 - t)
            if system.atlas.ready {
                size := radius * 3.2
                sparkle_tint := screen_pop_with_alpha(particle.accent, 1 - t)
                canvas2d.DrawTexturePro(
                    system.atlas,
                    screen_pop_atlas_source(system.atlas, .Sparkles),
                    {particle.position.x - size * .5, particle.position.y - size * .5, size, size},
                    sparkle_tint,
                )
                continue
            }
            canvas2d.DrawCircleV(particle.position, radius, color)
            for ray in 0 ..< 6 {
                angle := f32(ray) / 6 * math.TAU + f32(particle.seed & 31) * .03
                inner := radius * .55
                canvas2d.DrawLineEx(
                    {particle.position.x + math.cos(angle) * inner, particle.position.y + math.sin(angle) * inner},
                    {particle.position.x + math.cos(angle) * radius, particle.position.y + math.sin(angle) * radius},
                    2,
                    color,
                )
            }
            continue
        }

        if particle.sprite != .None && system.atlas.ready {
            bounds := screen_pop_bounds(&particle)
            canvas2d.DrawTexturePro(
                system.atlas,
                screen_pop_atlas_source(system.atlas, particle.sprite),
                bounds,
                particle.color,
            )
            continue
        }

        bounds := screen_pop_bounds(&particle)
        font_size := 20 * particle.scale
        shadow := screen_pop_with_alpha({5, 8, 14, 255}, .72)
        position := canvas2d.Vector2{bounds.x + 5 * particle.scale, bounds.y + 5 * particle.scale}
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            cstring(&particle.text[0]),
            {position.x + 2, position.y + 3},
            font_size,
            particle.scale,
            shadow,
        )
        canvas2d.DrawTextEx(canvas2d.Font{}, cstring(&particle.text[0]), position, font_size, particle.scale, particle.color)
    }
}

screen_pops_tick_and_draw :: proc(system: ^Screen_Pop_System, width, height: i32) {
    now := canvas2d.GetTime()
    if system.last_time == 0 do system.last_time = now
    dt := f32(now - system.last_time)
    system.last_time = now
    screen_pops_update(system, width, height, dt)
    screen_pops_draw(system)
}

screen_pops_lab: Screen_Pop_System
screen_pops_lab_phrase := 0
screen_pops_lab_sprite := Screen_Pop_Sprite.Nice
screen_pops_lab_style := SCREEN_POP_DEFAULT_STYLE
screen_pops_lab_count := 7
screen_pops_lab_dragging := -1
SCREEN_POPS_LAB_PHRASES := [?]string{"SPECIAL DELIVERY", "THE WIND IS CHANGING", "MIND THE GULLS", "POST HAS ARRIVED"}
SCREEN_POPS_LAB_COLORS := [?]canvas2d.Color {
    {255, 241, 196, 255},
    {255, 126, 103, 255},
    {255, 196, 54, 255},
    {95, 218, 209, 255},
    {196, 157, 232, 255},
    {235, 242, 245, 255},
}
SCREEN_POPS_LAB_SLIDER_COUNT :: 6

screen_pops_lab_panel :: proc(height: i32) -> canvas2d.Rectangle {
    return {18, 18, 286, min(f32(height - 36), f32(666))}
}

screen_pops_lab_slider_bounds :: proc(index: int) -> canvas2d.Rectangle {
    return {42, 132 + f32(index) * 43, 220, 20}
}

screen_pops_lab_slider_value :: proc(index: int) -> f32 {
    switch index {
    case 0:
        return f32(screen_pops_lab_count - 1) / 15
    case 1:
        return (screen_pops_lab_style.start_scale - .25) / 1.25
    case 2:
        return (screen_pops_lab_style.end_scale - 1) / 4
    case 3:
        return (screen_pops_lab_style.lifetime - .75) / 4.25
    case 4:
        return (screen_pops_lab_style.speed - 30) / 270
    case 5:
        return screen_pops_lab_style.push / 20
    }
    return 0
}

screen_pops_lab_set_slider :: proc(index: int, normalized: f32) {
    value := math.clamp(normalized, f32(0), f32(1))
    switch index {
    case 0:
        screen_pops_lab_count = 1 + int(math.round(value * 15))
    case 1:
        screen_pops_lab_style.start_scale = .25 + value * 1.25
    case 2:
        screen_pops_lab_style.end_scale = 1 + value * 4
    case 3:
        screen_pops_lab_style.lifetime = .75 + value * 4.25
    case 4:
        screen_pops_lab_style.speed = 30 + value * 270
    case 5:
        screen_pops_lab_style.push = value * 20
    }
}

screen_pops_lab_color_bounds :: proc(row, column: int) -> canvas2d.Rectangle {
    return {42 + f32(column) * 37, 422 + f32(row) * 64, 28, 28}
}

screen_pops_lab_sprite_bounds :: proc(index: int) -> canvas2d.Rectangle {
    column := index % 4
    row := index / 4
    return {42 + f32(column) * 54, 548 + f32(row) * 42, 48, 32}
}

screen_pops_lab_emit :: proc(width, height: i32) {
    phrase := SCREEN_POPS_LAB_PHRASES[screen_pops_lab_phrase]
    screen_pops_say(&screen_pops_lab, phrase, width, height, screen_pops_lab_count, screen_pops_lab_style)
    screen_pops_lab_phrase = (screen_pops_lab_phrase + 1) % len(SCREEN_POPS_LAB_PHRASES)
}

screen_pops_lab_emit_sprite :: proc(width, height: i32) {
    screen_pops_spawn_sprite(
        &screen_pops_lab,
        screen_pops_lab_sprite,
        width,
        height,
        screen_pops_lab_count,
        screen_pops_lab_style,
    )
    next := int(screen_pops_lab_sprite) + 1
    if next >= int(Screen_Pop_Sprite.Sparkles) do next = int(Screen_Pop_Sprite.Nice)
    screen_pops_lab_sprite = Screen_Pop_Sprite(next)
}

screen_pops_lab_emit_atlas :: proc(width, height: i32) {
    for sprite_value in int(Screen_Pop_Sprite.Nice) ..< int(Screen_Pop_Sprite.Sparkles) {
        screen_pops_spawn_sprite(
            &screen_pops_lab,
            Screen_Pop_Sprite(sprite_value),
            width,
            height,
            max(1, screen_pops_lab_count / 3),
            screen_pops_lab_style,
        )
    }
}

screen_pops_lab_configure :: proc(_: ^Editor, target: string) -> bool {
    screen_pops_reset(&screen_pops_lab)
    if !screen_pops_load_atlas(&screen_pops_lab) do return false
    screen_pops_lab_phrase = 0
    screen_pops_lab_sprite = .Nice
    screen_pops_lab_style = SCREEN_POP_DEFAULT_STYLE
    screen_pops_lab_count = 7
    screen_pops_lab_dragging = -1
    if target == "wind" do screen_pops_lab_phrase = 1
    if target == "gulls" do screen_pops_lab_phrase = 2
    if target == "post" do screen_pops_lab_phrase = 3
    screen_pops_lab_emit_atlas(max(canvas2d.GetScreenWidth(), 640), max(canvas2d.GetScreenHeight(), 360))
    return true
}

screen_pops_lab_process_input :: proc(editor: ^Editor) {
    mouse := canvas2d.GetMousePosition()
    pressed := canvas2d.IsMouseButtonPressed(.LEFT)
    panel := screen_pops_lab_panel(canvas2d.GetScreenHeight())
    if pressed {
        for index in 0 ..< SCREEN_POPS_LAB_SLIDER_COUNT {
            bounds := screen_pops_lab_slider_bounds(index)
            hit := canvas2d.Rectangle{bounds.x, bounds.y - 7, bounds.width, bounds.height + 14}
            if canvas2d.CheckCollisionPointRec(mouse, hit) {
                screen_pops_lab_dragging = index
                screen_pops_lab_set_slider(index, (mouse.x - bounds.x) / bounds.width)
                break
            }
        }
        for color, color_index in SCREEN_POPS_LAB_COLORS {
            if canvas2d.CheckCollisionPointRec(mouse, screen_pops_lab_color_bounds(0, color_index)) {
                screen_pops_lab_style.color = color
            }
            if canvas2d.CheckCollisionPointRec(mouse, screen_pops_lab_color_bounds(1, color_index)) {
                screen_pops_lab_style.accent = color
            }
        }
        for sprite_value in int(Screen_Pop_Sprite.Nice) ..< int(Screen_Pop_Sprite.Sparkles) {
            index := sprite_value - int(Screen_Pop_Sprite.Nice)
            if canvas2d.CheckCollisionPointRec(mouse, screen_pops_lab_sprite_bounds(index)) {
                screen_pops_lab_sprite = Screen_Pop_Sprite(sprite_value)
            }
        }
    }
    if canvas2d.IsMouseButtonDown(.LEFT) && screen_pops_lab_dragging >= 0 {
        bounds := screen_pops_lab_slider_bounds(screen_pops_lab_dragging)
        screen_pops_lab_set_slider(screen_pops_lab_dragging, (mouse.x - bounds.x) / bounds.width)
    }
    if canvas2d.IsMouseButtonReleased(.LEFT) do screen_pops_lab_dragging = -1

    if canvas2d.IsKeyPressed(.SPACE) || (pressed && !canvas2d.CheckCollisionPointRec(mouse, panel)) {
        screen_pops_lab_emit_sprite(canvas2d.GetScreenWidth(), canvas2d.GetScreenHeight())
    }
    if canvas2d.IsKeyPressed(.T) {
        screen_pops_lab_emit(canvas2d.GetScreenWidth(), canvas2d.GetScreenHeight())
    }
    if canvas2d.IsKeyPressed(.R) {
        screen_pops_reset(&screen_pops_lab)
        screen_pops_lab_emit_atlas(canvas2d.GetScreenWidth(), canvas2d.GetScreenHeight())
    }
    if canvas2d.IsKeyPressed(.ESCAPE) do lab_scene_exit_to_main_menu(editor)
}

screen_pops_lab_draw_controls :: proc(height: i32) {
    panel := screen_pops_lab_panel(height)
    canvas2d.DrawRectangleRounded(panel, .04, 8, {7, 14, 23, 252})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .04, 8, 1, {82, 111, 119, 255})
    ui_draw_text(.Label, "SCREEN POPS LAB", {42, 36}, .45, {255, 207, 116, 255})
    ui_draw_text(.Data, "SPACE / CLICK  POP    T  TEXT    R  ALL", {42, 67}, .12, {160, 192, 196, 255})
    ui_draw_text(.Data, "ESC  EXIT", {42, 89}, .12, {160, 192, 196, 255})

    names := [?]cstring{"COUNT", "START SIZE", "POP SIZE", "LIFETIME", "SPEED", "PUSH"}
    values := [?]cstring {
        fmt.ctprintf("%d", screen_pops_lab_count),
        fmt.ctprintf("%.2fx", screen_pops_lab_style.start_scale),
        fmt.ctprintf("%.2fx", screen_pops_lab_style.end_scale),
        fmt.ctprintf("%.2fs", screen_pops_lab_style.lifetime),
        fmt.ctprintf("%.0f", screen_pops_lab_style.speed),
        fmt.ctprintf("%.1f", screen_pops_lab_style.push),
    }
    for name, index in names {
        bounds := screen_pops_lab_slider_bounds(index)
        ui_draw_text(.Data, name, {bounds.x, bounds.y - 18}, .12, {183, 201, 204, 255})
        value_size := ui_measure_text(.Data, values[index], .12)
        ui_draw_text(
            .Data,
            values[index],
            {bounds.x + bounds.width - value_size.x, bounds.y - 18},
            .12,
            {255, 224, 164, 255},
        )
        canvas2d.DrawRectangleRounded({bounds.x, bounds.y + 4, bounds.width, 7}, 1, 4, {42, 59, 67, 255})
        normalized := screen_pops_lab_slider_value(index)
        canvas2d.DrawRectangleRounded({bounds.x, bounds.y + 4, bounds.width * normalized, 7}, 1, 4, {102, 186, 178, 255})
        canvas2d.DrawCircleV({bounds.x + bounds.width * normalized, bounds.y + 7.5}, 7, {224, 239, 224, 255})
    }

    ui_draw_text(.Data, "SPRITE TINT", {42, 398}, .12, {183, 201, 204, 255})
    ui_draw_text(.Data, "SPARKLE TINT", {42, 462}, .12, {183, 201, 204, 255})
    for color, color_index in SCREEN_POPS_LAB_COLORS {
        for row in 0 ..< 2 {
            bounds := screen_pops_lab_color_bounds(row, color_index)
            selected := row == 0 ? screen_pops_lab_style.color == color : screen_pops_lab_style.accent == color
            if selected {
                canvas2d.DrawRectangleRounded(
                    {bounds.x - 3, bounds.y - 3, bounds.width + 6, bounds.height + 6},
                    .25,
                    5,
                    {239, 239, 218, 255},
                )
            }
            canvas2d.DrawRectangleRounded(bounds, .25, 5, color)
        }
    }

    ui_draw_text(.Data, "SPRITE", {42, 524}, .12, {183, 201, 204, 255})
    labels := [?]cstring{"NICE", "LUCKY", "DLVR", "SPEC", "UNLK", "CREEP", "????", "WTF"}
    for label, index in labels {
        bounds := screen_pops_lab_sprite_bounds(index)
        sprite := Screen_Pop_Sprite(int(Screen_Pop_Sprite.Nice) + index)
        selected := sprite == screen_pops_lab_sprite
        fill := selected ? canvas2d.Color{97, 179, 171, 255} : canvas2d.Color{29, 47, 56, 255}
        if canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds) {
            fill = selected ? canvas2d.Color{118, 208, 198, 255} : canvas2d.Color{42, 64, 74, 255}
        }
        canvas2d.DrawRectangleRounded(bounds, .2, 5, fill)
        canvas2d.DrawRectangleRoundedLinesEx(
            bounds,
            .2,
            5,
            1,
            selected ? canvas2d.Color{231, 241, 217, 255} : canvas2d.Color{75, 101, 108, 255},
        )
        size := ui_measure_text(.Data, label, .08)
        ui_draw_text(.Data, label, {bounds.x + (bounds.width - size.x) * .5, bounds.y + 8}, .08, {235, 239, 224, 255})
    }
}

screen_pops_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    canvas2d.DrawRectangle(0, 0, width, height / 2, {8, 17, 29, 255})
    canvas2d.DrawRectangle(0, height / 2, width, height - height / 2, {24, 42, 51, 255})
    for ring in 0 ..< 5 {
        radius := f32(70 + ring * 74)
        canvas2d.DrawCircleV({f32(width) * .5, f32(height) * .5}, radius, {76, 116, 126, u8(10 - ring)})
    }
    screen_pops_tick_and_draw(&screen_pops_lab, width, height)
    screen_pops_lab_draw_controls(height)
}
