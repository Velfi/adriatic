package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"

cinematic_export_audio :: proc(kind: Capture_Kind, path: string) -> (duration: f32, handled, ok: bool) {
    #partial switch kind {
    case .Mouse_Theater:
        duration, ok = mouse_theater_export_audio(path)
        return duration, true, ok
    }
    return 0, false, false
}

cinematic_export_cli :: proc(args: []string) -> bool {
    if len(args) < 4 {
        fmt.eprintln(
            "usage: adriatic cinematic-export <mode> <output.mp4> [--audio track.wav] [--duration seconds] [--fps 1–60] [--target name] [--frames-dir directory]",
        )
        return false
    }
    mode, requested_output := args[2], args[3]
    kind, known := capture_kind_from_name(mode)
    if !known {
        fmt.eprintf("cinematic export: unknown capture mode %s\n", mode)
        return false
    }
    fps := 30
    duration := f32(0)
    audio_path := ""
    target := ""
    requested_frames := ""
    index := 4
    for index < len(args) {
        option := args[index]
        if index + 1 >= len(args) {
            fmt.eprintf("cinematic export: %s requires a value\n", option)
            return false
        }
        value := args[index + 1]
        switch option {
        case "--audio":
            audio_path = value
        case "--duration":
            parsed, ok := strconv.parse_f32(value)
            if !ok || parsed <= 0 || parsed > 3600 {
                fmt.eprintln("cinematic export: duration must be between 0 and 3600 seconds")
                return false
            }
            duration = parsed
        case "--fps":
            parsed, ok := strconv.parse_int(value)
            if !ok || parsed < 1 || parsed > 60 {
                fmt.eprintln("cinematic export: fps must be from 1 to 60")
                return false
            }
            fps = int(parsed)
        case "--target":
            target = value
        case "--frames-dir":
            requested_frames = value
        case:
            fmt.eprintf("cinematic export: unknown option %s\n", option)
            return false
        }
        index += 2
    }

    output, output_ok := adriatic_cli_absolute_path(requested_output)
    if !output_ok do return false
    frames_requested := requested_frames != "" ? requested_frames : fmt.tprintf("%s.frames", output)
    frames, frames_ok := adriatic_cli_absolute_path(frames_requested)
    if !frames_ok do return false
    if err := os.make_directory_all(frames); err != nil && err != .Exist {
        fmt.eprintf("cinematic export: cannot create frames directory %s: %v\n", frames, err)
        return false
    }
    if err := os.make_directory_all(os.dir(output)); err != nil && err != .Exist {
        fmt.eprintf("cinematic export: cannot create output directory: %v\n", err)
        return false
    }

    audio := audio_path
    if audio == "" {
        audio = fmt.tprintf("%s.wav", output)
        auto_duration, handled, audio_ok := cinematic_export_audio(kind, audio)
        if handled {
            if !audio_ok do return false
            if duration <= 0 do duration = auto_duration
        } else {
            audio = ""
        }
    } else {
        resolved, ok := adriatic_cli_absolute_path(audio)
        if !ok do return false
        audio = resolved
    }
    if duration <= 0 {
        fmt.eprintln(
            "cinematic export: this scene has no authored duration; provide --duration seconds",
        )
        return false
    }

    frame_count := max(int(math.ceil(f64(duration * f32(fps)))), 1)
    request := Capture_Request {
        kind            = kind,
        output_path     = frames,
        target          = target,
        window_width    = 1280,
        window_height   = 720,
        settle_frames   = 20,
        sequence_frames = frame_count,
        sequence_fps    = fps,
    }
    _ = adriatic_run(nil, request = &request)
    last_frame := fmt.tprintf("%s/frame-%06d.png", frames, frame_count - 1)
    if info, err := os.stat(last_frame, context.temp_allocator); err != nil || info.size == 0 {
        fmt.eprintf("cinematic export: image sequence ended before %s\n", last_frame)
        return false
    }

    ffmpeg := "ffmpeg"
    if configured := os.get_env("FFMPEG", context.temp_allocator); configured != "" do ffmpeg = configured
    frame_pattern := fmt.tprintf("%s/frame-%%06d.png", frames)
    command := make([dynamic]string, 0, 32, context.temp_allocator)
    append(
        &command,
        ffmpeg,
        "-y",
        "-hide_banner",
        "-loglevel",
        "warning",
        "-framerate",
        fmt.tprintf("%d", fps),
        "-i",
        frame_pattern,
    )
    if audio != "" do append(&command, "-i", audio)
    append(
        &command,
        "-t",
        fmt.tprintf("%.3f", duration),
        "-c:v",
        "libx264",
        "-crf",
        "17",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
    )
    if audio != "" do append(&command, "-c:a", "aac", "-b:a", "192k")
    append(&command, output)
    if !adriatic_cli_child(command[:]) do return false

    if info, err := os.stat(output, context.temp_allocator); err != nil || info.size == 0 {
        fmt.eprintf("cinematic export: FFmpeg did not write %s\n", output)
        return false
    }
    fmt.printf(
        "cinematic export: %d PNG frames + %s -> %s\n",
        frame_count,
        audio != "" ? audio : "silent track",
        output,
    )
    return true
}
