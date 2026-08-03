package main

import atmosphere "../packages/atmosphere"
import "core:fmt"
import "core:strconv"
import "core:strings"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

CONSOLE_INPUT_CAPACITY :: 512
CONSOLE_LINE_CAPACITY :: 128
CONSOLE_LINE_LENGTH :: 320
CONSOLE_HISTORY_CAPACITY :: 48

Console_Line_Kind :: enum {
    Info,
    Command,
    Error,
}

Console_Line :: struct {
    text:   [CONSOLE_LINE_LENGTH]u8,
    length: int,
    kind:   Console_Line_Kind,
}

Console_History_Entry :: struct {
    text:   [CONSOLE_INPUT_CAPACITY]u8,
    length: int,
}

Game_Console :: struct {
    open:                     bool,
    toggle_down:              bool,
    input:                    [CONSOLE_INPUT_CAPACITY]u8,
    input_length:             int,
    lines:                    [CONSOLE_LINE_CAPACITY]Console_Line,
    line_start:               int,
    line_count:               int,
    history:                  [CONSOLE_HISTORY_CAPACITY]Console_History_Entry,
    history_start:            int,
    history_count:            int,
    history_cursor:           int,
    watched_value:            int,
    autocomplete_hint:        [CONSOLE_INPUT_CAPACITY]u8,
    autocomplete_hint_length: int,
}

console_commands := [?]string {
    "help",
    "commands",
    "clear",
    "status",
    "physics",
    "get",
    "set",
    "watch",
    "unwatch",
    "time",
    "weather",
    "teleport",
    "lab",
    "quit",
}

console_values := [?]string {
    "player.position",
    "player.velocity",
    "camera.position",
    "world.time",
    "world.weather",
    "world.sea_level",
    "terrain.revision",
    "game.mode",
    "game.paused",
    "vehicle.kind",
}

console_copy :: proc(destination: []u8, source: string) -> int {
    count := min(len(destination), len(source))
    copy(destination[:count], transmute([]u8)source[:count])
    return count
}

console_input_text :: proc(state: ^Game_Console) -> string {
    if state == nil do return ""
    return string(state.input[:state.input_length])
}

console_line_text :: proc(line: ^Console_Line) -> string {
    if line == nil do return ""
    return string(line.text[:line.length])
}

console_set_input :: proc(state: ^Game_Console, text: string) {
    if state == nil do return
    state.input = {}
    state.input_length = console_copy(state.input[:], text)
}

console_append_input :: proc(state: ^Game_Console, text: string) {
    if state == nil || text == "" do return
    remaining := len(state.input) - state.input_length
    count := min(remaining, len(text))
    if count <= 0 do return
    copy(state.input[state.input_length:], transmute([]u8)text[:count])
    state.input_length += count
}

console_remove_last_rune :: proc(state: ^Game_Console) {
    if state == nil || state.input_length == 0 do return
    state.input_length -= 1
    for state.input_length > 0 && (state.input[state.input_length] & 0xc0) == 0x80 {
        state.input_length -= 1
    }
}

console_push_line :: proc(editor: ^Editor, text: string, kind: Console_Line_Kind = .Info) {
    if editor == nil do return
    state := &editor.console
    index := (state.line_start + state.line_count) % CONSOLE_LINE_CAPACITY
    if state.line_count == CONSOLE_LINE_CAPACITY {
        state.line_start = (state.line_start + 1) % CONSOLE_LINE_CAPACITY
        index = (state.line_start + state.line_count - 1) % CONSOLE_LINE_CAPACITY
    } else {
        state.line_count += 1
    }
    state.lines[index] = {}
    state.lines[index].length = console_copy(state.lines[index].text[:], text)
    state.lines[index].kind = kind
}

console_push_history :: proc(state: ^Game_Console, text: string) {
    if state == nil || text == "" do return
    if state.history_count > 0 {
        newest := (state.history_start + state.history_count - 1) % CONSOLE_HISTORY_CAPACITY
        previous := string(state.history[newest].text[:state.history[newest].length])
        if previous == text {
            state.history_cursor = state.history_count
            return
        }
    }
    index := (state.history_start + state.history_count) % CONSOLE_HISTORY_CAPACITY
    if state.history_count == CONSOLE_HISTORY_CAPACITY {
        state.history_start = (state.history_start + 1) % CONSOLE_HISTORY_CAPACITY
        index = (state.history_start + state.history_count - 1) % CONSOLE_HISTORY_CAPACITY
    } else {
        state.history_count += 1
    }
    state.history[index] = {}
    state.history[index].length = console_copy(state.history[index].text[:], text)
    state.history_cursor = state.history_count
}

console_history_move :: proc(state: ^Game_Console, direction: int) {
    if state == nil || state.history_count == 0 do return
    state.history_cursor = clamp(state.history_cursor + direction, 0, state.history_count)
    if state.history_cursor == state.history_count {
        console_set_input(state, "")
        return
    }
    index := (state.history_start + state.history_cursor) % CONSOLE_HISTORY_CAPACITY
    console_set_input(state, string(state.history[index].text[:state.history[index].length]))
}

console_words :: proc(text: string) -> (words: [16]string, count: int) {
    index := 0
    for index < len(text) {
        for index < len(text) && (text[index] == ' ' || text[index] == '\t') do index += 1
        if index >= len(text) do break
        start := index
        for index < len(text) && text[index] != ' ' && text[index] != '\t' do index += 1
        if count < len(words) {
            words[count] = text[start:index]
            count += 1
        }
    }
    return
}

console_value_index :: proc(name: string) -> int {
    for value, index in console_values {
        if value == name do return index
    }
    return -1
}

console_value :: proc(editor: ^Editor, index: int) -> string {
    if editor == nil do return "<no game>"
    switch index {
    case 0:
        p := editor.player.position
        return fmt.tprintf("(%.2f, %.2f, %.2f)", p.x, p.y, p.z)
    case 1:
        v := editor.player.velocity
        return fmt.tprintf("(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
    case 2:
        p := editor.camera_pose.position
        return fmt.tprintf("(%.2f, %.2f, %.2f)", p.x, p.y, p.z)
    case 3:
        return fmt.tprintf("%.2f minutes", editor.atmosphere.world_minutes)
    case 4:
        return fmt.tprintf("%v", editor.atmosphere.override)
    case 5:
        return fmt.tprintf("%.2f", editor.project.sea_level)
    case 6:
        return fmt.tprintf("%d", editor.project.revision)
    case 7:
        if !editor.in_map do return "editor"
        return fmt.tprintf("%v", editor.pilot.mode)
    case 8:
        return pause_menu_is_open(editor) ? "true" : "false"
    case 9:
        if !editor.in_map do return "none"
        if driving_aircraft(editor) do return fmt.tprintf("%v", editor.aircraft.active)
        if driving_car(editor) do return "car"
        return "on-foot"
    }
    return "<unknown>"
}

console_print_value :: proc(editor: ^Editor, name: string) {
    index := console_value_index(name)
    if index < 0 {
        console_push_line(editor, fmt.tprintf("Unknown live value '%s'. Try get <Tab>.", name), .Error)
        return
    }
    console_push_line(editor, fmt.tprintf("%s = %s", name, console_value(editor, index)))
}

console_set_value :: proc(editor: ^Editor, name, text: string) {
    value, ok := strconv.parse_f32(text)
    if !ok {
        console_push_line(editor, fmt.tprintf("'%s' is not a number", text), .Error)
        return
    }
    switch name {
    case "world.time":
        atmosphere.set_world_minutes(&editor.atmosphere, value)
    case "world.sea_level":
        editor.project.sea_level = value
        editor.project.revision += 1
    case:
        console_push_line(editor, fmt.tprintf("'%s' is read-only or unknown", name), .Error)
        return
    }
    console_print_value(editor, name)
}

console_help :: proc(editor: ^Editor, command: string = "") {
    if command == "" {
        console_push_line(editor, "help [command] | commands | status | clear")
        console_push_line(editor, "get/set/watch <live.value> | unwatch")
        console_push_line(editor, "time <hour> | weather <auto|clear|windy|storm> | weather-front")
        console_push_line(editor, "teleport <x> <y> <z> | lab <name> [target] | quit")
        console_push_line(editor, "Tab completes; Up/Down recalls history; ~ closes")
        return
    }
    if command == "get" do console_push_line(editor, "get <live.value> — print current reflected state")
    if command == "set" do console_push_line(editor, "set <live.value> <number> — set a writable value")
    if command == "watch" do console_push_line(editor, "watch <live.value> — pin a live value above the prompt")
    if command == "time" do console_push_line(editor, "time <hour> — set time using a 24-hour clock")
    if command == "weather" do console_push_line(editor, "weather <auto|clear|windy|storm>")
    if command == "weather-front" do console_push_line(editor, "weather-front — print active spatial front and local conditions")
    if command == "teleport" do console_push_line(editor, "teleport <x> <y> <z> — move the player")
    if command == "physics" do console_push_line(editor, "physics — print shared-world bodies and active soft bodies")
    if command == "lab" {
        console_push_line(editor, "lab list — list registered lab scenes")
        console_push_line(editor, "lab <name> [target] — switch to a lab using its normal loader")
        console_push_line(editor, "lab exit — leave the lab and return to the main menu")
    }
}

console_lab_list :: proc(editor: ^Editor) {
    console_push_line(editor, "Registered labs:")
    for definition in LAB_SCENES do console_push_line(editor, fmt.tprintf("  %s", definition.name))
}

console_lab_load :: proc(editor: ^Editor, name: string, target: string = "") -> bool {
    definition := lab_scene_find(name)
    if definition == nil {
        console_push_line(editor, fmt.tprintf("Unknown lab '%s'. Use lab list.", name), .Error)
        return false
    }
    if !lab_scene_load(editor, {definition = definition, target = target}) {
        console_push_line(editor, fmt.tprintf("Lab '%s' failed to configure", name), .Error)
        return false
    }
    console_push_line(
        editor,
        fmt.tprintf("Loaded lab '%s'%s", name, target == "" ? "" : fmt.tprintf(" target '%s'", target)),
    )
    return true
}

console_execute :: proc(editor: ^Editor, source: string) {
    command_line := strings.trim_space(source)
    if command_line == "" do return
    console_push_history(&editor.console, command_line)
    console_push_line(editor, fmt.tprintf("> %s", command_line), .Command)
    words, count := console_words(command_line)
    if count == 0 do return
    command := words[0]
    switch command {
    case "help":
        console_help(editor, count > 1 ? words[1] : "")
    case "commands":
        console_push_line(
            editor,
            "help, commands, clear, status, physics, get, set, watch, unwatch, time, weather, teleport, lab, quit",
        )
    case "clear":
        editor.console.line_start = 0
        editor.console.line_count = 0
    case "status":
        for name, index in console_values do console_push_line(editor, fmt.tprintf("%s = %s", name, console_value(editor, index)))
    case "physics":
        stats := physics.get_world_stats(editor.gameplay_physics.world)
        console_push_line(
            editor,
            fmt.tprintf(
                "physics bodies=%d active=%d soft=%d static=%d boats=%d",
                stats.body_count,
                stats.active_body_count,
                stats.soft_body_count,
                len(editor.gameplay_physics.static_bodies),
                editor.gameplay_physics.boat_count,
            ),
        )
    case "get":
        if count < 2 do console_push_line(editor, "Usage: get <live.value>", .Error)
        if count >= 2 do console_print_value(editor, words[1])
    case "set":
        if count < 3 do console_push_line(editor, "Usage: set <live.value> <number>", .Error)
        if count >= 3 do console_set_value(editor, words[1], words[2])
    case "watch":
        if count < 2 {
            console_push_line(editor, "Usage: watch <live.value>", .Error)
        } else if index := console_value_index(words[1]); index >= 0 {
            editor.console.watched_value = index + 1
            console_push_line(editor, fmt.tprintf("Watching %s", words[1]))
        } else {
            console_push_line(editor, fmt.tprintf("Unknown live value '%s'", words[1]), .Error)
        }
    case "unwatch":
        editor.console.watched_value = 0
        console_push_line(editor, "Watch cleared")
    case "time":
        if count < 2 {
            console_print_value(editor, "world.time")
        } else if hour, ok := strconv.parse_f32(words[1]); ok {
            atmosphere.set_world_minutes(&editor.atmosphere, hour * 60)
            console_print_value(editor, "world.time")
        } else {
            console_push_line(editor, "Usage: time <hour>", .Error)
        }
    case "weather":
        if count < 2 {
            console_print_value(editor, "world.weather")
        } else {
            switch words[1] {
            case "auto", "automatic":
                atmosphere.set_weather_override(&editor.atmosphere, .Automatic)
            case "clear":
                atmosphere.set_weather_override(&editor.atmosphere, .Clear)
            case "windy":
                atmosphere.set_weather_override(&editor.atmosphere, .Windy)
            case "storm":
                atmosphere.set_weather_override(&editor.atmosphere, .Storm)
            case:
                console_push_line(editor, "Weather must be auto, clear, windy, or storm", .Error)
                return
            }
            console_print_value(editor, "world.weather")
        }
    case "weather-front":
        local := atmosphere_local_weather(editor, editor.camera_pose.position)
        if editor.atmosphere.schedule.front.active {
            front := &editor.atmosphere.schedule.front
            console_push_line(
                editor,
                fmt.tprintf(
                    "Front %u: %.0f%%, %.0f s remaining, width %.0f m, speed %.2f m/s",
                    front.event_id,
                    atmosphere.front_progress(&editor.atmosphere) * 100,
                    atmosphere.front_seconds_until_next(&editor.atmosphere),
                    front.width,
                    front.speed,
                ),
            )
        } else {
            console_push_line(
                editor,
                fmt.tprintf(
                    "No active front; next event in %.0f s",
                    atmosphere.front_seconds_until_next(&editor.atmosphere),
                ),
            )
        }
        console_push_line(
            editor,
            fmt.tprintf(
                "Local: severity %.2f rain %.2f gust %.2f wind %.1f %.1f %.1f",
                local.severity,
                local.precipitation,
                local.gust_strength,
                local.wind[0],
                local.wind[1],
                local.wind[2],
            ),
        )
    case "teleport":
        if count != 4 {
            console_push_line(editor, "Usage: teleport <x> <y> <z>", .Error)
        } else {
            x, x_ok := strconv.parse_f32(words[1])
            y, y_ok := strconv.parse_f32(words[2])
            z, z_ok := strconv.parse_f32(words[3])
            if !x_ok || !y_ok || !z_ok {
                console_push_line(editor, "Teleport coordinates must be numbers", .Error)
            } else {
                player_place(editor, {x, y, z}, .Teleport, editor.player.facing_yaw_radians, false)
                console_print_value(editor, "player.position")
            }
        }
    case "lab":
        if count >= 2 && words[1] == "exit" {
            lab_scene_exit_to_main_menu(editor)
            console_set_open(editor, false)
        } else if count < 2 || words[1] == "list" {
            console_lab_list(editor)
        } else {
            target := count >= 3 ? words[2] : ""
            _ = console_lab_load(editor, words[1], target)
        }
    case "quit":
        editor.quit_requested = true
    case:
        console_push_line(editor, fmt.tprintf("Unknown command '%s'. Type help.", command), .Error)
    }
}

console_completion :: proc(state: ^Game_Console, apply: bool) {
    if state == nil do return
    input := console_input_text(state)
    words, count := console_words(input)
    candidates := console_commands[:]
    lab_names: [len(LAB_SCENES) + 2]string
    fragment := count > 0 ? words[count - 1] : ""
    prefix := ""
    if count > 1 || (count == 1 && strings.has_suffix(input, " ")) {
        if words[0] == "get" || words[0] == "set" || words[0] == "watch" {
            candidates = console_values[:]
        } else if words[0] == "lab" {
            lab_names[0] = "list"
            lab_names[1] = "exit"
            for definition, index in LAB_SCENES do lab_names[index + 2] = definition.name
            candidates = lab_names[:]
        } else {
            return
        }
        if strings.has_suffix(input, " ") {
            fragment = ""
            prefix = input
        } else {
            prefix = input[:len(input) - len(fragment)]
        }
    }
    match := ""
    matches := 0
    for candidate in candidates {
        if strings.has_prefix(candidate, fragment) {
            match = candidate
            matches += 1
        }
    }
    state.autocomplete_hint = {}
    state.autocomplete_hint_length = 0
    if matches == 1 {
        completed := fmt.tprintf("%s%s", prefix, match)
        if apply {
            console_set_input(state, fmt.tprintf("%s ", completed))
        } else {
            state.autocomplete_hint_length = console_copy(state.autocomplete_hint[:], completed)
        }
    }
}

console_set_open :: proc(editor: ^Editor, open: bool) {
    if editor == nil || editor.console.open == open do return
    editor.console.open = open
    editor.console.history_cursor = editor.console.history_count
    if open {
        _ = canvas2d.StartTextInput()
        if editor.console.line_count == 0 {
            console_push_line(editor, "ADRIATIC DEVELOPER CONSOLE")
            console_push_line(editor, "Type help for commands. Tab autocompletes.")
        }
        set_pointer_locked(false)
        _ = sdl.ShowCursor()
    } else {
        _ = canvas2d.StopTextInput()
        set_pointer_locked(editor.in_map && !pause_menu_is_open(editor))
    }
}

console_process_input :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil do return
    state := &editor.console
    keys := sdl.GetKeyboardState(nil)
    toggle_down := keys[int(sdl.Scancode.GRAVE)]
    if toggle_down && !state.toggle_down do console_set_open(editor, !state.open)
    state.toggle_down = toggle_down
    if !state.open do return

    prompt_y := min(f32(height) * .56, f32(470)) - 43
    _ = canvas2d.SetTextInputArea(
        {14, prompt_y - 5, f32(width - 28), 34},
        int(ui_measure_text(.Data, fmt.ctprintf("> %s", console_input_text(state)), .3).x),
    )
    console_append_input(state, canvas2d.GetTextInput())

    if canvas2d.IsKeyPressed(.BACKSPACE) do console_remove_last_rune(state)
    if canvas2d.IsKeyPressed(.UP) do console_history_move(state, -1)
    if canvas2d.IsKeyPressed(.DOWN) do console_history_move(state, 1)
    if canvas2d.IsKeyPressed(.TAB) do console_completion(state, true)
    if canvas2d.IsKeyPressed(.ESCAPE) {
        console_set_open(editor, false)
        return
    }
    if canvas2d.IsKeyPressed(.ENTER) {
        console_execute(editor, console_input_text(state))
        console_set_input(state, "")
        state.history_cursor = state.history_count
    }
    console_completion(state, false)
}

console_draw :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil || !editor.console.open do return
    state := &editor.console
    panel_height := min(f32(height) * .56, f32(470))
    canvas2d.DrawRectangle(0, 0, width, i32(panel_height), {7, 13, 18, 242})
    canvas2d.DrawRectangle(0, i32(panel_height) - 2, width, 2, {74, 211, 200, 255})
    ui_draw_text(.Label, "DEVELOPER CONSOLE", {20, 14}, .4, {105, 231, 220, 255})
    ui_draw_text(.Data, "~ CLOSES  |  TAB COMPLETES  |  UP/DOWN HISTORY", {210, 17}, .2, {128, 145, 157, 255})

    prompt_y := panel_height - 43
    if state.watched_value > 0 {
        index := state.watched_value - 1
        watch := fmt.ctprintf("WATCH  %s = %s", console_values[index], console_value(editor, index))
        ui_draw_text(.Data, watch, {20, prompt_y - 27}, .2, {241, 188, 93, 255})
    }
    canvas2d.DrawRectangle(14, i32(prompt_y) - 5, width - 28, 34, {18, 29, 36, 255})
    canvas2d.DrawRectangleRoundedLinesEx({14, prompt_y - 5, f32(width - 28), 34}, .04, 4, 1, {60, 81, 92, 255})
    input := console_input_text(state)
    prompt := fmt.ctprintf("> %s", input)
    ui_draw_text(.Data, prompt, {22, prompt_y + 3}, .3, {235, 241, 243, 255})

    composition := canvas2d.GetTextInputComposition()
    if composition.text != "" {
        prompt_size := ui_measure_text(.Data, prompt, .3)
        ui_draw_text(
            .Data,
            fmt.ctprintf("%s", composition.text),
            {22 + prompt_size.x, prompt_y + 3},
            .3,
            {241, 188, 93, 255},
        )
    } else if state.autocomplete_hint_length > 0 {
        hint := string(state.autocomplete_hint[:state.autocomplete_hint_length])
        typed_size := ui_measure_text(.Data, prompt, .3)
        suffix := hint[min(len(input), len(hint)):]
        ui_draw_text(.Data, fmt.ctprintf("%s", suffix), {22 + typed_size.x, prompt_y + 3}, .3, {91, 112, 123, 255})
    }
    if int(canvas2d.GetTime() * 2) % 2 == 0 {
        cursor_size := ui_measure_text(.Data, prompt, .3)
        canvas2d.DrawRectangle(i32(24 + cursor_size.x), i32(prompt_y + 3), 2, 17, {105, 231, 220, 255})
    }

    line_height := f32(21)
    available_lines := max(1, int((prompt_y - 58) / line_height))
    draw_count := min(state.line_count, available_lines)
    first := state.line_count - draw_count
    y := prompt_y - 35 - f32(draw_count) * line_height
    for offset in 0 ..< draw_count {
        logical := first + offset
        index := (state.line_start + logical) % CONSOLE_LINE_CAPACITY
        line := &state.lines[index]
        color := canvas2d.Color{189, 203, 210, 255}
        if line.kind == .Command do color = {105, 231, 220, 255}
        if line.kind == .Error do color = {242, 125, 112, 255}
        ui_draw_text(.Data, fmt.ctprintf("%s", console_line_text(line)), {22, y}, .2, color)
        y += line_height
    }
}
