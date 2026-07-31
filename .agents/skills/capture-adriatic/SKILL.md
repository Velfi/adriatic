---
name: capture-adriatic
description: Build and run Adriatic's deterministic command-line capture and cinematic export tools to produce PNG screenshots, animated GIFs, MP4 videos, or vehicle turntable frames. Use when the user asks to capture, render, animate, or inspect a specific Adriatic scene, lab, mode, named target, camera angle, resolution, GIF, video, cinematic, or turntable from the built app. Do not use for a screenshot of the already-running game; use hotshot for that live workflow.
---

# Capture Adriatic

Use the built app's `capture` or `cinematic-export` command. They launch a short-lived macOS app for an authored, deterministic render; they do not record the currently running editor.

## Workflow

1. Work from the Adriatic repository root.
2. If `build/dev/adriatic` is absent, stale, or the user asks for current code, run `make build`. Allow GUI execution and sibling `../zelda-engine` build writes if the sandbox requests them.
3. When the scene mode is unclear, inspect `build/dev/adriatic --help`. Do not maintain or copy target lists. For a running game, discover instantiated subjects with the MCP `selector_query` tool. For deterministic capture, select subjects dynamically after the requested mode has instantiated its scene.
4. Choose an absolute PNG output path under `build/captures/` unless the user supplies one. Use a descriptive filename and avoid overwriting unrelated captures.
5. Run one of:

   ```sh
   build/dev/adriatic capture <mode> <absolute-output.png> [target]
   build/dev/adriatic capture <mode> --output <absolute-output.png> [options]
   build/dev/adriatic capture <mode> --output <absolute-output.png> --select <kind[:identity]> [selector options]
   ```

   The process launches the macOS app briefly. Request GUI permission when required.
6. Treat a nonzero exit or missing/empty output as failure. After success, inspect the PNG visually and retry with corrected target, camera, dimensions, or settle frames if the requested subject is not presented well.
7. Return the absolute output path and render the image in the final response.

## GIFs

For a plant-wind review, prefer the existing end-to-end tool:

```sh
python3 tools/plant_wind_gif.py --species <name> --weather <calm|windy|storm> --output <absolute-output.gif>
```

Use its `--frames`, `--width`, `--height`, `--fps`, and `--keep-frames` controls as needed. It captures deterministic phases and uses FFmpeg palette generation for a clean seamless loop.

For other modes, create a deterministic PNG sequence first. Use `cinematic-export` with `--frames-dir` when the mode has time-based animation, or `capture vehicle-showcase --turntable-frames` for a turntable. Assemble a looping GIF with FFmpeg using a generated palette; do not convert a single capture or screen-record the app. Keep intermediate frames only when the user requests them or they are useful for diagnosis. Verify that the GIF is non-empty and inspect representative frames before returning it.

## Videos

Use the existing cinematic exporter for MP4:

```sh
build/dev/adriatic cinematic-export <mode> <absolute-output.mp4> --duration <seconds> --fps <1-60> [--target <name>] [--audio <track.wav>] [--frames-dir <directory>]
```

The exporter captures 1280x720 deterministic PNG frames and invokes FFmpeg to encode H.264/yuv420p. `mouse-theater` can supply authored audio and duration; other modes require `--duration`. Pass `--audio` only when the user supplies or requests a track. Use an absolute frames directory when frames should be retained or inspected. Treat a nonzero exit or missing/empty MP4 as failure, inspect representative source frames, and report the video plus any retained frames directory.

## Options

Use the binary's help as the source of truth. Common controls are `--target`, `--width`, `--height`, `--settle-frames`, `--camera-orbit`, `--camera-distance`, and `--camera-offset`. Supply `--camera-eye` and `--camera-look-at` together; do not combine them with relative camera controls.

For a vehicle turntable, pass `--turntable-frames <1-360>` with mode `vehicle-showcase` and use an output directory rather than a PNG path. Verify every generated frame and report the directory.

## Dynamic selectors

Prefer `--select` over adding capture-specific target names when the requested subject already exists in the instantiated scene:

```sh
build/dev/adriatic capture map --output /absolute/zora.png --select character:zora --presentation portrait
build/dev/adriatic capture vehicle-showcase --output /absolute/postale.png --select vehicle:postale
build/dev/adriatic capture building --output /absolute/building.png --select structure:42
build/dev/adriatic capture editor --output /absolute/selected.png --select selection
```

Supported runtime kinds are `character`, `vehicle`, `structure`, `prop`, `plant`, and `selection`. Identity matching is case-insensitive and accepts the subject name, subtype, or numeric stable ID. Selectors enumerate authoritative runtime collections; do not add parallel name lists.

Use repeatable `--where key=value` filters for `id`, `name`, `kind`, `type`, `resident`, `archetype`, or `available`. An ambiguous selector fails by default. Resolve it explicitly with `--pick first` or a one-based `--pick N`. Presentations are `fit`, `portrait`, `profile`, `overhead`, and `authored`.

Scene setup and subject selection are separate. Existing mode/target setup may still be required to instantiate a particular story state, pose, lab species, or cutscene beat; `--select` then chooses and frames an object from that state.

For the already-running game, use MCP `selector_query` to discover matches and `selector_focus` to focus the inspection camera. Those tools accept the same selector, filters, pick, and presentation concepts as deterministic capture.

For the special bougainvillea batch, use:

```sh
build/dev/adriatic capture bougainvillea [output-directory] [seed ...]
```

## Boundaries

- Do not restart an already-running game merely to capture its current frame; use `$hotshot`.
- Do not use `make capture-live`; that is also the live-game request workflow.
- Require FFmpeg for GIF and MP4 assembly. If it is missing, report that dependency instead of silently substituting a nondeterministic screen recording.
- Do not diagnose rendering or memory defects from a normal capture alone. Reproduce user-reported rendering or memory problems with `make validation` as required by the repository instructions.
