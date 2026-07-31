package cinematic

// Renderer-independent cinematic scripting and deterministic playback.
//
// Scripts are borrowed slices: authored Shot storage must outlive Playback.
// A shot owns a camera move and may end in a wipe. Sample exposes both camera
// views during the transition so renderers can composite them directly; a
// renderer may instead hide the cut with a colored mask.

Vec3 :: [3]f32

Ease :: enum {
    Linear,
    Smooth,
    Smoother,
}

Wipe_Kind :: enum {
    None,
    Left,
    Right,
    Up,
    Down,
    Iris,
    Clockwise,
    Checker,
}

Wipe :: struct {
    kind:     Wipe_Kind,
    duration: f32,
    softness: f32,
    color:    [4]u8,
}

Camera :: struct {
    position:     Vec3,
    target:       Vec3,
    focal_length: f32,
}

Shot :: struct {
    id:          string,
    duration:    f32,
    camera_from: Camera,
    camera_to:   Camera,
    ease:        Ease,
    wipe_out:    Wipe,
}

Script :: struct {
    id:    string,
    shots: []Shot,
    loop:  bool,
}

Playback :: struct {
    script:     ^Script,
    shot_index: int,
    shot_time:  f32,
    playing:    bool,
    completed:  bool,
    revision:   u64,
}

Sample :: struct {
    camera:        Camera,
    // During a wipe these are the two independently renderable views. A
    // renderer can draw camera_from first, then draw camera_to through a mask
    // driven by wipe_progress. Renderers without that facility may keep using
    // camera and cover the cut with the wipe color.
    camera_from:   Camera,
    camera_to:     Camera,
    shot_id:       string,
    shot_index:    int,
    shot_progress: f32,
    wipe:          Wipe,
    wipe_progress: f32,
    playing:       bool,
}

default_wipe_color :: [4]u8{5, 8, 12, 255}

wipe :: proc(kind: Wipe_Kind, duration: f32 = .65, color := default_wipe_color) -> Wipe {
    return {kind = kind, duration = max(duration, 0), color = color}
}

camera :: proc(position, target: Vec3, focal_length: f32 = 1.35) -> Camera {
    return {position = position, target = target, focal_length = focal_length}
}

hold :: proc(id: string, duration: f32, value: Camera, wipe_out := Wipe{}) -> Shot {
    return {id = id, duration = duration, camera_from = value, camera_to = value, ease = .Smooth, wipe_out = wipe_out}
}

move :: proc(id: string, duration: f32, from, to: Camera, ease := Ease.Smooth, wipe_out := Wipe{}) -> Shot {
    return {id = id, duration = duration, camera_from = from, camera_to = to, ease = ease, wipe_out = wipe_out}
}

valid :: proc(script: ^Script) -> bool {
    if script == nil || len(script.shots) == 0 do return false
    total_duration := f32(0)
    for shot in script.shots {
        if shot.duration < 0 || shot.wipe_out.duration < 0 do return false
        total_duration += shot.duration
    }
    if script.loop && total_duration <= 0 do return false
    return true
}

play :: proc(playback: ^Playback, script: ^Script) -> bool {
    if playback == nil || !valid(script) do return false
    playback^ = {
        script   = script,
        playing  = true,
        revision = playback.revision + 1,
    }
    return true
}

stop :: proc(playback: ^Playback) {
    if playback == nil do return
    playback.playing = false
    playback.completed = true
    playback.revision += 1
}

ease_value :: proc(kind: Ease, value: f32) -> f32 {
    t := clamp(value, 0, 1)
    switch kind {
    case .Linear:
        return t
    case .Smooth:
        return t * t * (3 - 2 * t)
    case .Smoother:
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
    return t
}

@(no_instrumentation)
lerp_vec3 :: #force_inline proc(a, b: Vec3, t: f32) -> Vec3 {
    return a + (b - a) * t
}

lerp_camera :: proc(a, b: Camera, t: f32) -> Camera {
    return {
        position = lerp_vec3(a.position, b.position, t),
        target = lerp_vec3(a.target, b.target, t),
        focal_length = a.focal_length + (b.focal_length - a.focal_length) * t,
    }
}

// A shot's wipe occupies its final duration. It covers during the first half,
// the shot advances at full cover, and the second half reveals the new shot.
// outgoing_wipe lets the new shot retain the transition authored by its
// predecessor without copying any script data.
outgoing_wipe :: proc(playback: ^Playback) -> (Wipe, f32) {
    if playback == nil || playback.script == nil do return {}, 0
    shots := playback.script.shots
    if playback.shot_index < 0 || playback.shot_index >= len(shots) do return {}, 0
    shot := shots[playback.shot_index]
    wipe_value := shot.wipe_out
    if wipe_value.kind == .None || wipe_value.duration <= 0 do return {}, 0
    start := max(shot.duration - wipe_value.duration * .5, 0)
    if playback.shot_time < start do return {}, 0
    return wipe_value, clamp((playback.shot_time - start) / max(wipe_value.duration, .0001), 0, .5)
}

incoming_wipe :: proc(playback: ^Playback) -> (Wipe, f32) {
    if playback == nil || playback.script == nil || playback.shot_index <= 0 do return {}, 0
    previous := playback.script.shots[playback.shot_index - 1]
    wipe_value := previous.wipe_out
    if wipe_value.kind == .None || wipe_value.duration <= 0 do return {}, 0
    half := wipe_value.duration * .5
    if playback.shot_time >= half do return {}, 0
    return wipe_value, .5 + playback.shot_time / max(wipe_value.duration, .0001)
}

step :: proc(playback: ^Playback, delta_seconds: f32) {
    if playback == nil || !playback.playing || playback.script == nil do return
    shots := playback.script.shots
    remaining := max(delta_seconds, 0)
    for remaining > 0 && playback.playing {
        shot := shots[playback.shot_index]
        duration := max(shot.duration, 0)
        available := max(duration - playback.shot_time, 0)
        advance := min(remaining, available)
        playback.shot_time += advance
        remaining -= advance
        if playback.shot_time < duration do break

        next := playback.shot_index + 1
        if next >= len(shots) {
            if playback.script.loop {
                next = 0
                playback.revision += 1
            } else {
                playback.playing = false
                playback.completed = true
                playback.shot_time = duration
                playback.revision += 1
                break
            }
        }
        playback.shot_index = next
        playback.shot_time = 0
        playback.revision += 1
        if available <= 0 && remaining <= 0 do break
    }
}

sample :: proc(playback: ^Playback) -> Sample {
    result: Sample
    if playback == nil || playback.script == nil || len(playback.script.shots) == 0 do return result
    index := clamp(playback.shot_index, 0, len(playback.script.shots) - 1)
    shot := playback.script.shots[index]
    progress := shot.duration <= 0 ? f32(1) : clamp(playback.shot_time / shot.duration, 0, 1)
    result = {
        camera        = lerp_camera(shot.camera_from, shot.camera_to, ease_value(shot.ease, progress)),
        camera_from   = lerp_camera(shot.camera_from, shot.camera_to, ease_value(shot.ease, progress)),
        camera_to     = lerp_camera(shot.camera_from, shot.camera_to, ease_value(shot.ease, progress)),
        shot_id       = shot.id,
        shot_index    = index,
        shot_progress = progress,
        playing       = playback.playing,
    }
    result.wipe, result.wipe_progress = outgoing_wipe(playback)
    if result.wipe.kind != .None && index + 1 < len(playback.script.shots) {
        result.camera_from = result.camera
        result.camera_to = playback.script.shots[index + 1].camera_from
    }
    incoming, incoming_progress := incoming_wipe(playback)
    if incoming.kind != .None {
        result.wipe, result.wipe_progress = incoming, incoming_progress
        result.camera_from = playback.script.shots[index - 1].camera_to
        result.camera_to = result.camera
    }
    return result
}
