package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
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
    fmt.println("  adriatic fixture-upgrade [--dry-run] <file-or-directory>")
    fmt.println("  adriatic map bake <output.adriatic-map> [--seed <west,east>]")
    fmt.println("  adriatic map validate <map.adriatic-map>")
    fmt.println("  adriatic map import <legacy.terrain> <output.adriatic-map>")
    fmt.println("  adriatic dialogue-preview <output.wav> [preset] [text] [formant-shift] [base-pitch] [expression]")
    fmt.println(
        "  adriatic cinematic-export <mode> <output.mp4> [--audio track.wav] [--duration seconds] [--fps 1–60]",
    )
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
    fmt.println("    --turntable-frames <n> capture a 360° sequence into the output directory (1–360)")
    fmt.println(
        "    --select <kind[:id]>  dynamically select character, vehicle, structure, prop, plant, or selection",
    )
    fmt.println("    --where <key=value>   filter selected subjects; repeat up to 8 times")
    fmt.println("    --pick <first|n>      choose a deterministic match when the selector is ambiguous")
    fmt.println("    --presentation <name> fit, portrait, profile, overhead, or authored")
    fmt.println("    --emote <name>        pose the player with a named mouse emote")
    fmt.println("    --emote-time <0..1>   freeze the emote at normalized time (default 0.5)")
    fmt.println("    --emote-hand <side>   left or right (default right)")
    fmt.println("    --emote-seed <n>      deterministic unsigned variation seed")
    fmt.println("    --emote-target <x,y,z> optional world-space attention target")
    fmt.println("    --emote-headgear <name> override mouse headgear for the capture matrix")
    fmt.println("    --emote-scarf <on|off> override scarf visibility")
    fmt.println("    --emote-mailbag <on|off> override mailbag visibility")
    fmt.println("    --emote-ground-normal <x,y,z> test the pose on a normalized mild slope")
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
        "  grass-wind, screen-pops, wildflower-lab, rainbow-lab, shadow-lab, boat-lab, car-generator-lab, patio-lab, garden-lab, plant-generator, leaf-generator, flower-generator, fountain-generator, cemetery-generator, estuary-delta, windmill-generator, hero-building, lighthouse-lab, mouse-gait-lab, mouse-theater, rondine-movement-lab, markov-wreck, markov-farmland, markov-marina, ruins-lab",
    )
    fmt.println("  markov-city, markov-town, markov-village, aegean-city, aegean-town, aegean-village")
    fmt.println("  narrow, compact, sky-noon, sky-sunrise, sky-sunset, sky-storm, sky-night, player-*")
    fmt.println(
        "  weather-maestral, weather-bura-clear, weather-bura-storm, weather-jugo, weather-calm-humid, weather-post-front",
    )
    fmt.println("")
    fmt.println("labs:")
    fmt.println("  loading-screen")
    for definition in LAB_SCENES do fmt.printf("  %s\n", definition.name)
}

adriatic_cli_map :: proc(args: []string) -> bool {
    if len(args) < 4 {
        adriatic_cli_usage()
        return false
    }
    command := args[2]
    if command == "validate" {
        if len(args) != 4 {
            fmt.eprintln("adriatic map validate expects exactly one path")
            return false
        }
        artifact, error, valid := map_artifact_read(args[3])
        defer map_artifact_error_dispose(&error)
        if !valid {
            fmt.eprintf("map validate: %s failed: %v %s\n", args[3], error.kind, error.message)
            return false
        }
        defer map_artifact_destroy(artifact)
        fmt.printf(
            "map validate: %s format=%d generator=%d structures=%d\n",
            args[3],
            MAP_ARTIFACT_FORMAT_VERSION,
            artifact.generator_version,
            artifact.project.structure_count,
        )
        return true
    }
    if command == "bake" {
        seeds := terrain.DEFAULT_ISLAND_SEEDS
        if len(args) > 4 {
            if len(args) != 6 || args[4] != "--seed" {
                fmt.eprintln("adriatic map bake accepts only --seed <west,east>")
                return false
            }
            values := strings.split(args[5], ",", context.temp_allocator)
            if len(values) != len(seeds) {
                fmt.eprintf("adriatic map bake expects %d comma-separated seeds\n", len(seeds))
                return false
            }
            for value, index in values {
                parsed, ok := strconv.parse_int(value)
                if !ok || parsed <= 0 || parsed > 0xffffffff {
                    fmt.eprintf("adriatic map bake has invalid seed: %s\n", value)
                    return false
                }
                seeds[index] = u32(parsed)
            }
        }
        parent := os.dir(args[3])
        if parent != "." {
            if directory_error := os.make_directory_all(parent); directory_error != nil && directory_error != .Exist {
                fmt.eprintf("map bake: cannot create %s: %v\n", parent, directory_error)
                return false
            }
        }
        fmt.printf("map bake: generating %s\n", args[3])
        artifact, generate_error, generated := map_artifact_generate(seeds)
        defer map_artifact_error_dispose(&generate_error)
        if !generated {
            fmt.eprintf("map bake: generation failed: %v %s\n", generate_error.kind, generate_error.message)
            return false
        }
        defer map_artifact_destroy(artifact)
        write_error, written := map_artifact_write(artifact, args[3])
        defer map_artifact_error_dispose(&write_error)
        if !written {
            fmt.eprintf("map bake: write failed: %v %s\n", write_error.kind, write_error.message)
            return false
        }
        fmt.printf("map bake: wrote %s\n", args[3])
        return true
    }
    if command == "import" {
        if len(args) != 5 {
            fmt.eprintln("adriatic map import expects a legacy terrain path and output path")
            return false
        }
        editor := new(Editor)
        defer {
            structure_storage_destroy(editor)
            free(editor)
        }
        if !terrain.load_project(&editor.project, args[3]) {
            fmt.eprintf("map import: cannot load legacy terrain %s\n", args[3])
            return false
        }
        settlement_path, settlement_path_error := filepath.join(
            []string{os.dir(args[3]), SETTLEMENT_BRUSH_STORE_PATH},
            context.temp_allocator,
        )
        if settlement_path_error == nil do _ = settlement_brush_store_load(&editor.settlement_plan, settlement_path)
        artifact, capture_error, captured := map_artifact_capture(editor)
        defer map_artifact_error_dispose(&capture_error)
        if !captured do return false
        defer map_artifact_destroy(artifact)
        write_error, written := map_artifact_write(artifact, args[4])
        defer map_artifact_error_dispose(&write_error)
        if !written {
            fmt.eprintf("map import: write failed: %v %s\n", write_error.kind, write_error.message)
            return false
        }
        fmt.printf("map import: wrote %s\n", args[4])
        return true
    }
    fmt.eprintf("adriatic: unknown map command: %s\n", command)
    return false
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

adriatic_cli_parse_bounded_int :: proc(option, value: string, minimum, maximum: int) -> (int, bool) {
    parsed, ok := strconv.parse_int(value)
    if !ok || parsed < minimum || parsed > maximum {
        fmt.eprintf("adriatic: %s must be an integer from %d to %d, got %s\n", option, minimum, maximum, value)
        return 0, false
    }
    return int(parsed), true
}

adriatic_cli_parse_f32_components :: proc(option, value: string, count: int) -> ([3]f32, bool) {
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
    if args[1] == "fixture-upgrade" do return true, adriatic_cli_fixture_upgrade(args)
    if args[1] == "map" do return true, adriatic_cli_map(args)
    if args[1] == "dialogue-preview" do return true, dialogue_voice_preview_cli(args)
    if args[1] == "cinematic-export" do return true, cinematic_export_cli(args)
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
    turntable_frames := 0
    camera_eye, camera_look_at, camera_offset: [3]f32
    camera_orbit: [2]f32
    camera_eye_set, camera_look_at_set := false, false
    camera_orbit_set, camera_distance_set, camera_offset_set := false, false, false
    camera_distance: f32
    list_targets := false
    selector, selector_pick, presentation := "", "", "fit"
    selector_filters: [CAPTURE_SELECTOR_FILTER_CAPACITY]string
    selector_filter_count := 0
    emote_name := ""
    emote_time: f32
    emote_time_set := false
    emote_handedness := Mouse_Emote_Handedness.Right
    emote_seed: u32
    emote_target: [3]f32
    emote_target_set := false
    emote_headgear := Mouse_Accessory.None
    emote_headgear_set := false
    emote_scarf, emote_scarf_set := false, false
    emote_mailbag, emote_mailbag_set := true, false
    emote_ground_normal: [3]f32
    emote_ground_normal_set := false
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
           argument == "--camera-offset" ||
           argument == "--turntable-frames" ||
           argument == "--select" ||
           argument == "--where" ||
           argument == "--pick" ||
           argument == "--presentation" ||
           argument == "--emote" ||
           argument == "--emote-time" ||
           argument == "--emote-hand" ||
           argument == "--emote-seed" ||
           argument == "--emote-target" ||
           argument == "--emote-headgear" ||
           argument == "--emote-scarf" ||
           argument == "--emote-mailbag" ||
           argument == "--emote-ground-normal" {
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
            case "--turntable-frames":
                parsed, ok := adriatic_cli_parse_bounded_int(argument, value, 1, 360)
                if !ok do return true, false
                turntable_frames = parsed
            case "--select":
                if selector != "" {
                    fmt.eprintln("adriatic: --select was specified more than once")
                    return true, false
                }
                selector = value
            case "--where":
                if selector_filter_count >= len(selector_filters) {
                    fmt.eprintf("adriatic: at most %d --where filters are supported\n", len(selector_filters))
                    return true, false
                }
                selector_filters[selector_filter_count] = value
                selector_filter_count += 1
            case "--pick":
                if selector_pick != "" {
                    fmt.eprintln("adriatic: --pick was specified more than once")
                    return true, false
                }
                selector_pick = value
            case "--presentation":
                presentation = value
            case "--emote":
                if _, ok := mouse_emote_from_name(value); !ok || value == "none" {
                    fmt.eprintf("adriatic: unknown emote: %s\n", value)
                    return true, false
                }
                emote_name = value
            case "--emote-time":
                parsed, ok := strconv.parse_f32(value)
                if !ok || math.is_nan(parsed) || math.is_inf(parsed) || parsed < 0 || parsed > 1 {
                    fmt.eprintf("adriatic: --emote-time must be from 0 to 1, got %s\n", value)
                    return true, false
                }
                emote_time, emote_time_set = parsed, true
            case "--emote-hand":
                if value != "left" && value != "right" {
                    fmt.eprintf("adriatic: --emote-hand must be left or right, got %s\n", value)
                    return true, false
                }
                emote_handedness = value == "left" ? Mouse_Emote_Handedness.Left : Mouse_Emote_Handedness.Right
            case "--emote-seed":
                parsed, ok := strconv.parse_int(value)
                if !ok || parsed < 0 || parsed > 0xffffffff {
                    fmt.eprintf("adriatic: --emote-seed must be an unsigned 32-bit integer, got %s\n", value)
                    return true, false
                }
                emote_seed = u32(parsed)
            case "--emote-target":
                parsed, ok := adriatic_cli_parse_f32_components(argument, value, 3)
                if !ok do return true, false
                emote_target, emote_target_set = parsed, true
            case "--emote-headgear":
                switch value {
                case "none":
                    emote_headgear = .None
                case "goggles":
                    emote_headgear = .Goggles
                case "flower":
                    emote_headgear = .Flower
                case "acorn-cap":
                    emote_headgear = .Acorn_Cap
                case "bottle-cap":
                    emote_headgear = .Bottle_Cap
                case "paper-boat":
                    emote_headgear = .Paper_Boat
                case "chef-hat":
                    emote_headgear = .Chef_Hat
                case "ushanka":
                    emote_headgear = .Ushanka
                case "beret":
                    emote_headgear = .Beret
                case "alpine-hat":
                    emote_headgear = .Alpine_Hat
                case "flat-cap":
                    emote_headgear = .Flat_Cap
                case "sailor-hat":
                    emote_headgear = .Sailor_Hat
                case:
                    fmt.eprintf("adriatic: unknown mouse headgear: %s\n", value)
                    return true, false
                }
                emote_headgear_set = true
            case "--emote-scarf":
                if value != "on" && value != "off" {
                    fmt.eprintf("adriatic: --emote-scarf must be on or off, got %s\n", value)
                    return true, false
                }
                emote_scarf, emote_scarf_set = value == "on", true
            case "--emote-mailbag":
                if value != "on" && value != "off" {
                    fmt.eprintf("adriatic: --emote-mailbag must be on or off, got %s\n", value)
                    return true, false
                }
                emote_mailbag, emote_mailbag_set = value == "on", true
            case "--emote-ground-normal":
                parsed, ok := adriatic_cli_parse_f32_components(argument, value, 3)
                if !ok do return true, false
                length_squared := parsed[0] * parsed[0] + parsed[1] * parsed[1] + parsed[2] * parsed[2]
                if length_squared < .0001 || parsed[1] <= 0 {
                    fmt.eprintln("adriatic: --emote-ground-normal must be a nonzero upward vector")
                    return true, false
                }
                inverse_length := 1 / f32(math.sqrt(f64(length_squared)))
                emote_ground_normal = {
                    parsed[0] * inverse_length,
                    parsed[1] * inverse_length,
                    parsed[2] * inverse_length,
                }
                emote_ground_normal_set = true
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
    if selector == "" && (selector_filter_count > 0 || selector_pick != "" || presentation != "fit") {
        fmt.eprintln("adriatic: --where, --pick, and --presentation require --select")
        return true, false
    }
    if emote_name == "" &&
       (emote_time_set ||
               emote_target_set ||
               emote_seed != 0 ||
               emote_handedness == .Left ||
               emote_headgear_set ||
               emote_scarf_set ||
               emote_mailbag_set ||
               emote_ground_normal_set) {
        fmt.eprintln("adriatic: emote time, hand, seed, and target require --emote")
        return true, false
    }
    if emote_name != "" && target == "" do target = "player-three-quarter"
    if selector != "" {
        _, selector_error, selector_ok := capture_selector_parse(
            selector,
            selector_filters,
            selector_filter_count,
            selector_pick,
        )
        if !selector_ok {
            fmt.eprintf("adriatic: invalid selector: %s\n", selector_error)
            return true, false
        }
        if !capture_presentation_valid(presentation) {
            fmt.eprintf("adriatic: unknown presentation: %s\n", presentation)
            return true, false
        }
    }
    if turntable_frames > 0 && kind != .Vehicle_Showcase {
        fmt.eprintln("adriatic: --turntable-frames currently requires capture mode vehicle-showcase")
        return true, false
    }
    if turntable_frames > 0 && target == "" do target = "car"
    if camera_eye_set != camera_look_at_set {
        fmt.eprintln("adriatic: --camera-eye and --camera-look-at must be provided together")
        return true, false
    }
    if camera_eye_set && (camera_orbit_set || camera_distance_set || camera_offset_set || turntable_frames > 0) {
        fmt.eprintln(
            "adriatic: explicit --camera-eye/--camera-look-at cannot be combined with relative camera or turntable options",
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
    output_directory := turntable_frames > 0 ? output : os.dir(output)
    if err := os.make_directory_all(output_directory); err != nil && err != .Exist {
        fmt.eprintf("adriatic: cannot create output directory: %v\n", err)
        return true, false
    }
    if target == "" && len(mode) >= 6 && mode[:6] == "player" do target = mode
    if turntable_frames == 0 {
        if err := os.remove(output); err != nil && err != .Not_Exist {
            fmt.eprintf("adriatic: cannot replace %s: %v\n", output, err)
            return true, false
        }
    } else {
        for frame_index in 0 ..< turntable_frames {
            frame_path := fmt.tprintf("%s/frame-%03d.png", output, frame_index)
            if err := os.remove(frame_path); err != nil && err != .Not_Exist {
                fmt.eprintf("adriatic: cannot replace %s: %v\n", frame_path, err)
                return true, false
            }
        }
    }
    request := Capture_Request {
        kind                    = kind,
        output_path             = output,
        target                  = target,
        window_width            = window_width,
        window_height           = window_height,
        settle_frames           = settle_frames,
        camera_eye              = camera_eye,
        camera_look_at          = camera_look_at,
        camera_eye_set          = camera_eye_set,
        camera_look_at_set      = camera_look_at_set,
        camera_orbit_degrees    = camera_orbit,
        camera_orbit_set        = camera_orbit_set,
        camera_distance         = camera_distance,
        camera_distance_set     = camera_distance_set,
        camera_offset           = camera_offset,
        camera_offset_set       = camera_offset_set,
        turntable_frames        = turntable_frames,
        selector                = selector,
        selector_filters        = selector_filters,
        selector_filter_count   = selector_filter_count,
        selector_pick           = selector_pick,
        presentation            = presentation,
        emote_name              = emote_name,
        emote_time              = emote_time,
        emote_time_set          = emote_time_set,
        emote_handedness        = emote_handedness,
        emote_seed              = emote_seed,
        emote_target            = emote_target,
        emote_target_set        = emote_target_set,
        emote_headgear          = emote_headgear,
        emote_headgear_set      = emote_headgear_set,
        emote_scarf             = emote_scarf,
        emote_scarf_set         = emote_scarf_set,
        emote_mailbag           = emote_mailbag,
        emote_mailbag_set       = emote_mailbag_set,
        emote_ground_normal     = emote_ground_normal,
        emote_ground_normal_set = emote_ground_normal_set,
    }
    _ = adriatic_run(nil, request = &request)
    if request.selector_failed do return true, false
    if turntable_frames > 0 {
        for frame_index in 0 ..< turntable_frames {
            frame_path := fmt.tprintf("%s/frame-%03d.png", output, frame_index)
            info, screenshot_error := os.stat(frame_path, context.temp_allocator)
            if screenshot_error != nil || info.size == 0 {
                fmt.eprintf("adriatic: turntable did not write a non-empty image to %s\n", frame_path)
                return true, false
            }
        }
        fmt.printf("turntable: wrote %d frames to %s\n", turntable_frames, output)
    } else {
        info, screenshot_error := os.stat(output, context.temp_allocator)
        if screenshot_error != nil || info.size == 0 {
            fmt.eprintf("adriatic: capture did not write a non-empty image to %s\n", output)
            return true, false
        }
    }
    return true, true
}
