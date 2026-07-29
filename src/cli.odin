package main

import architecture "../packages/architecture"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

adriatic_cli_usage :: proc() {
    fmt.println("usage:")
    fmt.println("  adriatic")
    fmt.println("  adriatic --shadow-lab")
    fmt.println("  adriatic --lab <name> [target]")
    fmt.println("  adriatic dialogue-preview <output.wav> [preset] [text] [formant-shift] [base-pitch] [expression]")
    fmt.println("  adriatic capture <mode> <output.png> [target]")
    fmt.println("  adriatic capture <mode> --output <output.png> [options]")
    fmt.println("    --target <name>       capture-specific target")
    fmt.println("    --width <pixels>      window width (320–7680)")
    fmt.println("    --height <pixels>     window height (240–4320)")
    fmt.println("    --settle-frames <n>   frame to capture (0–4096)")
    fmt.println("    --camera-eye <x,y,z>  explicit camera position")
    fmt.println("    --camera-look-at <x,y,z> explicit camera target")
    fmt.println("    --camera-orbit <yaw,pitch> adjust authored camera in degrees")
    fmt.println("    --camera-distance <n> set distance from camera target")
    fmt.println("    --camera-offset <x,y,z> translate authored camera and target")
    fmt.println("    --list-targets        list registered targets for this mode")
    fmt.println("    building targets: <ordinal>, ground-<ordinal>, cypress, mouse-town")
    fmt.println("  adriatic capture bougainvillea [output-directory] [seed ...]")
    fmt.println("")
    fmt.println("modes:")
    fmt.println("  editor, formation, map, flight, car, vehicle-showcase, paint-mode")
    fmt.println("  road, road-dust, road-grip, terrain-grip, building, story-meeting")
    fmt.println("  foliage, foliage-forest, foliage-forest-low, foliage-understory")
    fmt.println("  foliage-forest-golden, foliage-forest-wind-a, foliage-forest-wind-b")
    fmt.println("  foliage-forest-low-wind-a, foliage-forest-low-wind-b, foliage-stress")
    fmt.println(
        "  grass-wind, wildflower-lab, shadow-lab, boat-lab, mouse-gait-lab, rondine-movement-lab, markov-wreck, markov-farmland, markov-marina",
    )
    fmt.println("  markov-city, markov-town, markov-village, aegean-city, aegean-town, aegean-village")
    fmt.println("  narrow, compact, sky-noon, sky-sunset, sky-storm, sky-night, player-*")
    fmt.println("")
    fmt.println("labs:")
    fmt.println("  loading-screen")
    for definition in LAB_SCENES do fmt.printf("  %s\n", definition.name)
}

adriatic_cli_child :: proc(command: []string) -> bool {
    process, start_error := os.process_start(
        {command = command, stdin = os.stdin, stdout = os.stdout, stderr = os.stderr},
    )
    if start_error != nil {
        fmt.eprintf("adriatic: failed to start capture: %v\n", start_error)
        return false
    }
    state, wait_error := os.process_wait(process)
    if wait_error != nil {
        fmt.eprintf("adriatic: failed while waiting for capture: %v\n", wait_error)
        return false
    }
    return state.success
}

adriatic_cli_absolute_path :: proc(path: string) -> (string, bool) {
    if filepath.is_abs(path) do return path, true
    working_directory, err := os.get_working_directory(context.temp_allocator)
    if err != nil {
        fmt.eprintf("adriatic: cannot resolve current directory: %v\n", err)
        return "", false
    }
    absolute, join_error := filepath.join([]string{working_directory, path}, context.temp_allocator)
    if join_error != nil {
        fmt.eprintf("adriatic: cannot resolve %s: %v\n", path, join_error)
        return "", false
    }
    return absolute, true
}

adriatic_cli_bougainvillea :: proc(args: []string) -> bool {
    requested_output := len(args) >= 4 ? args[3] : "build/captures/bougainvillea-seeds"
    output_directory, resolved := adriatic_cli_absolute_path(requested_output)
    if !resolved do return false
    if err := os.make_directory_all(output_directory); err != nil && err != .Exist {
        fmt.eprintf("adriatic: cannot create %s: %v\n", output_directory, err)
        return false
    }
    defaults := architecture.BOUGAINVILLEA_VALIDATION_SEEDS
    custom_count := max(len(args) - 4, 0)
    count := custom_count > 0 ? custom_count : len(defaults)
    for index in 0 ..< count {
        seed := u32(0)
        if custom_count > 0 {
            seed_arg := args[4 + index]
            parsed, ok := strconv.parse_int(seed_arg)
            if !ok || parsed < 0 || parsed > 0xffffffff {
                fmt.eprintf("adriatic: invalid unsigned 32-bit seed: %s\n", seed_arg)
                return false
            }
            seed = u32(parsed)
        } else {
            seed = defaults[index]
        }
        output, _ := filepath.join(
            []string{output_directory, fmt.tprintf("seed-%d.png", seed)},
            context.temp_allocator,
        )
        target := fmt.tprintf("bougainvillea-%d", seed)
        command := [5]string{args[0], "capture", "building", output, target}
        fmt.printf("capture seed %d -> %s\n", seed, output)
        if !adriatic_cli_child(command[:]) do return false
    }
    return true
}

adriatic_cli_parse_bounded_int :: proc(
    option, value: string,
    minimum, maximum: int,
) -> (int, bool) {
    parsed, ok := strconv.parse_int(value)
    if !ok || parsed < minimum || parsed > maximum {
        fmt.eprintf(
            "adriatic: %s must be an integer from %d to %d, got %s\n",
            option,
            minimum,
            maximum,
            value,
        )
        return 0, false
    }
    return int(parsed), true
}

adriatic_cli_parse_f32_components :: proc(
    option, value: string,
    count: int,
) -> ([3]f32, bool) {
    result: [3]f32
    parts := strings.split(value, ",", context.temp_allocator)
    if len(parts) != count {
        fmt.eprintf("adriatic: %s expects %d comma-separated numbers, got %s\n", option, count, value)
        return result, false
    }
    for component in 0 ..< count {
        parsed, ok := strconv.parse_f32(parts[component])
        if !ok || math.is_nan(parsed) || math.is_inf(parsed) {
            fmt.eprintf("adriatic: %s contains an invalid number: %s\n", option, parts[component])
            return result, false
        }
        result[component] = parsed
    }
    return result, true
}

adriatic_cli :: proc(args: []string) -> (handled, success: bool) {
    if len(args) < 2 do return false, true
    if args[1] == "help" || args[1] == "--help" || args[1] == "-h" {
        adriatic_cli_usage()
        return true, true
    }
    if args[1] == "dialogue-preview" do return true, dialogue_voice_preview_cli(args)
    if args[1] != "capture" do return false, true
    if len(args) < 3 {
        adriatic_cli_usage()
        return true, false
    }
    mode := args[2]
    if mode == "bougainvillea" do return true, adriatic_cli_bougainvillea(args)
    kind, known := capture_kind_from_name(mode)
    if !known {
        fmt.eprintf("adriatic: unknown capture mode: %s\n", mode)
        adriatic_cli_usage()
        return true, false
    }
    requested_output := ""
    target := ""
    window_width, window_height := 0, 0
    settle_frames := -1
    camera_eye, camera_look_at, camera_offset: [3]f32
    camera_orbit: [2]f32
    camera_eye_set, camera_look_at_set := false, false
    camera_orbit_set, camera_distance_set, camera_offset_set := false, false, false
    camera_distance: f32
    list_targets := false
    positional_count := 0
    index := 3
    for index < len(args) {
        argument := args[index]
        if argument == "--list-targets" {
            if list_targets {
                fmt.eprintln("adriatic: --list-targets was specified more than once")
                return true, false
            }
            list_targets = true
            index += 1
            continue
        }
        if argument == "--output" ||
           argument == "--target" ||
           argument == "--width" ||
           argument == "--height" ||
           argument == "--settle-frames" ||
           argument == "--camera-eye" ||
           argument == "--camera-look-at" ||
           argument == "--camera-orbit" ||
           argument == "--camera-distance" ||
           argument == "--camera-offset" {
            if index + 1 >= len(args) {
                fmt.eprintf("adriatic: %s requires a value\n", argument)
                return true, false
            }
            value := args[index + 1]
            switch argument {
            case "--output":
                if requested_output != "" {
                    fmt.eprintln("adriatic: output path was specified more than once")
                    return true, false
                }
                requested_output = value
            case "--target":
                if target != "" {
                    fmt.eprintln("adriatic: target was specified more than once")
                    return true, false
                }
                target = value
            case "--width":
                parsed, ok := adriatic_cli_parse_bounded_int(argument, value, 320, 7680)
                if !ok do return true, false
                window_width = parsed
            case "--height":
                parsed, ok := adriatic_cli_parse_bounded_int(argument, value, 240, 4320)
                if !ok do return true, false
                window_height = parsed
            case "--settle-frames":
                parsed, ok := adriatic_cli_parse_bounded_int(argument, value, 0, 4096)
                if !ok do return true, false
                settle_frames = parsed
            case "--camera-eye":
                parsed, ok := adriatic_cli_parse_f32_components(argument, value, 3)
                if !ok do return true, false
                camera_eye, camera_eye_set = parsed, true
            case "--camera-look-at":
                parsed, ok := adriatic_cli_parse_f32_components(argument, value, 3)
                if !ok do return true, false
                camera_look_at, camera_look_at_set = parsed, true
            case "--camera-orbit":
                parsed, ok := adriatic_cli_parse_f32_components(argument, value, 2)
                if !ok do return true, false
                camera_orbit = {parsed[0], parsed[1]}
                camera_orbit_set = true
            case "--camera-distance":
                parsed, ok := strconv.parse_f32(value)
                if !ok || math.is_nan(parsed) || math.is_inf(parsed) || parsed < .01 || parsed > 100000 {
                    fmt.eprintf("adriatic: %s must be a number from 0.01 to 100000, got %s\n", argument, value)
                    return true, false
                }
                camera_distance, camera_distance_set = parsed, true
            case "--camera-offset":
                parsed, ok := adriatic_cli_parse_f32_components(argument, value, 3)
                if !ok do return true, false
                camera_offset, camera_offset_set = parsed, true
            }
            index += 2
            continue
        }
        if len(argument) >= 2 && argument[:2] == "--" {
            fmt.eprintf("adriatic: unknown capture option: %s\n", argument)
            return true, false
        }
        if positional_count == 0 {
            if requested_output != "" {
                fmt.eprintln("adriatic: output path was specified more than once")
                return true, false
            }
            requested_output = argument
        } else if positional_count == 1 {
            if target != "" {
                fmt.eprintln("adriatic: target was specified more than once")
                return true, false
            }
            target = argument
        } else {
            fmt.eprintf("adriatic: unexpected capture argument: %s\n", argument)
            return true, false
        }
        positional_count += 1
        index += 1
    }
    if list_targets {
        targets := capture_targets(kind)
        if len(targets) == 0 {
            fmt.printf("adriatic: capture mode %s has no registered named targets\n", mode)
        } else {
            fmt.printf("%s targets:\n", mode)
            for name in targets do fmt.printf("  %s\n", name)
        }
        return true, true
    }
    if requested_output == "" {
        fmt.eprintf("adriatic: capture %s requires an output path\n", mode)
        return true, false
    }
    if camera_eye_set != camera_look_at_set {
        fmt.eprintln("adriatic: --camera-eye and --camera-look-at must be provided together")
        return true, false
    }
    if camera_eye_set && (camera_orbit_set || camera_distance_set || camera_offset_set) {
        fmt.eprintln(
            "adriatic: explicit --camera-eye/--camera-look-at cannot be combined with relative camera options",
        )
        return true, false
    }
    if camera_eye_set {
        dx := camera_eye[0] - camera_look_at[0]
        dy := camera_eye[1] - camera_look_at[1]
        dz := camera_eye[2] - camera_look_at[2]
        if dx * dx + dy * dy + dz * dz < 1e-6 {
            fmt.eprintln("adriatic: --camera-eye must differ from --camera-look-at")
            return true, false
        }
    }
    output, resolved := adriatic_cli_absolute_path(requested_output)
    if !resolved do return true, false
    if err := os.make_directory_all(os.dir(output)); err != nil && err != .Exist {
        fmt.eprintf("adriatic: cannot create output directory: %v\n", err)
        return true, false
    }
    if target == "" && len(mode) >= 6 && mode[:6] == "player" do target = mode
    if err := os.remove(output); err != nil && err != .Not_Exist {
        fmt.eprintf("adriatic: cannot replace %s: %v\n", output, err)
        return true, false
    }
    request := Capture_Request {
        kind          = kind,
        output_path   = output,
        target        = target,
        window_width  = window_width,
        window_height = window_height,
        settle_frames = settle_frames,
        camera_eye = camera_eye,
        camera_look_at = camera_look_at,
        camera_eye_set = camera_eye_set,
        camera_look_at_set = camera_look_at_set,
        camera_orbit_degrees = camera_orbit,
        camera_orbit_set = camera_orbit_set,
        camera_distance = camera_distance,
        camera_distance_set = camera_distance_set,
        camera_offset = camera_offset,
        camera_offset_set = camera_offset_set,
    }
    _ = adriatic_run(nil, request = &request)
    info, screenshot_error := os.stat(output, context.temp_allocator)
    if screenshot_error != nil || info.size == 0 {
        fmt.eprintf("adriatic: capture did not write a non-empty image to %s\n", output)
        return true, false
    }
    return true, true
}
