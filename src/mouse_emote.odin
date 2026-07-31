package main

import third_person "../packages/third_person"
import "core:math"
import "core:testing"

// Mouse emotes are procedural pose contributions, not clips. Keep this stable
// identity independent of UI text so dialogue, live control, and capture all
// address the same runtime actions.
Mouse_Emote :: enum u8 {
    None,
    Wave,
    Cheer,
    Bow,
    Point,
    Shrug,
    Sniff,
    Curious_Head_Tilt,
    Surprised_Recoil,
    Sit,
    Groom,
    Pick_Up_Hold,
    Sleep,
    Synthetic_Test,
}

Mouse_Emote_Phase :: enum u8 {
    Inactive,
    Anticipation,
    Performance,
    Hold,
    Recovery,
    Blend_Out,
}

Mouse_Emote_Handedness :: enum u8 {
    Left,
    Right,
}

Mouse_Emote_Target :: struct {
    position:    third_person.Vec3,
    valid:       bool,
    world_space: bool,
}

Mouse_Emote_State :: struct {
    action:              Mouse_Emote,
    phase:               Mouse_Emote_Phase,
    elapsed_seconds:     f32,
    phase_seconds:       f32,
    normalized_time:     f32,
    blend_weight:        f32,
    loop_count:          u32,
    loop_limit:          u32,
    cancelling:          bool,
    frozen:              bool,
    scrub_enabled:       bool,
    scrub_normalized:    f32,
    handedness:          Mouse_Emote_Handedness,
    target:              Mouse_Emote_Target,
    variation_seed:      u32,
    playback_revision:   u64,
}

Mouse_Emote_Inputs :: struct {
    movement_intent: f32,
    horizontal_speed: f32,
    grounded: bool,
    player_controlled: bool,
    incompatible_pose: bool,
    paused: bool,
}

Mouse_Emote_Bone_Pose :: struct {
    position: third_person.Vec3,
    pitch:    f32,
    yaw:      f32,
    roll:     f32,
    weight:   f32,
}

Mouse_Emote_Ear_Pose :: struct {
    position: third_person.Vec3,
    yaw:      f32,
    roll:     f32,
    weight:   f32,
}

Mouse_Emote_Paw_Pose :: struct {
    local_offset: third_person.Vec3,
    weight:       f32,
    planted:      bool,
}

Mouse_Emote_Tail_Pose :: struct {
    local_direction: third_person.Vec3,
    lift:            f32,
    curl:            f32,
    tip:             f32,
    weight:          f32,
}

Mouse_Emote_Channel :: enum u8 {
    Lower_Body,
    Upper_Body,
    Head,
    Ears,
    Fore_Paws,
    Hind_Paws,
    Tail,
    Secondary,
}

Mouse_Emote_Pose :: struct {
    channels:         bit_set[Mouse_Emote_Channel],
    bones:            [5]Mouse_Emote_Bone_Pose,
    ears:             [2]Mouse_Emote_Ear_Pose,
    paws:             [4]Mouse_Emote_Paw_Pose, // LF, LH, RF, RH
    tail:             Mouse_Emote_Tail_Pose,
    body_height:      f32,
    body_compression: f32,
    breathing_weight: f32,
    blink_weight:     f32,
    idle_weight:      f32,
}

MOUSE_EMOTE_ANTICIPATION_SECONDS :: f32(.18)
MOUSE_EMOTE_PERFORMANCE_SECONDS :: f32(.72)
MOUSE_EMOTE_RECOVERY_SECONDS :: f32(.22)
MOUSE_EMOTE_BLEND_OUT_SECONDS :: f32(.14)
MOUSE_EMOTE_MOVEMENT_INTENT_CANCEL :: f32(.16)
MOUSE_EMOTE_SPEED_CANCEL :: f32(.18)

mouse_emote_name :: proc(action: Mouse_Emote) -> string {
    switch action {
    case .None: return "none"
    case .Wave: return "wave"
    case .Cheer: return "cheer"
    case .Bow: return "bow"
    case .Point: return "point"
    case .Shrug: return "shrug"
    case .Sniff: return "sniff"
    case .Curious_Head_Tilt: return "curious-head-tilt"
    case .Surprised_Recoil: return "surprised-recoil"
    case .Sit: return "sit"
    case .Groom: return "groom"
    case .Pick_Up_Hold: return "pick-up-hold"
    case .Sleep: return "sleep"
    case .Synthetic_Test: return "synthetic-test"
    }
    return "none"
}

mouse_emote_from_name :: proc(name: string) -> (Mouse_Emote, bool) {
    for action in Mouse_Emote {
        if action != .None && mouse_emote_name(action) == name do return action, true
    }
    if name == "none" do return .None, true
    return .None, false
}

mouse_emote_reset :: proc(state: ^Mouse_Emote_State) {
    if state == nil do return
    revision := state.playback_revision + 1
    state^ = {}
    state.playback_revision = revision
}

mouse_emote_start :: proc(
    state: ^Mouse_Emote_State,
    action: Mouse_Emote,
    handedness := Mouse_Emote_Handedness.Right,
    target := Mouse_Emote_Target{},
    variation_seed := u32(0),
    loop_limit := u32(0),
) -> bool {
    if state == nil || action == .None do return false
    revision := state.playback_revision + 1
    state^ = {
        action            = action,
        phase             = .Anticipation,
        handedness        = handedness,
        target            = target,
        variation_seed    = variation_seed,
        loop_limit        = loop_limit,
        playback_revision = revision,
    }
    return true
}

mouse_emote_cancel :: proc(state: ^Mouse_Emote_State) {
    if state == nil || state.action == .None || state.phase == .Blend_Out do return
    state.phase = .Blend_Out
    state.phase_seconds = 0
    state.cancelling = true
}

mouse_emote_active :: proc(state: ^Mouse_Emote_State) -> bool {
    return state != nil && state.action != .None && state.phase != .Inactive
}

mouse_emote_smoothstep :: proc(value: f32) -> f32 {
    t := clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
}

mouse_emote_target_local :: proc(
    target: Mouse_Emote_Target,
    origin: third_person.Vec3,
    yaw_radians: f32,
) -> (third_person.Vec3, bool) {
    if !target.valid do return {}, false
    delta := target.position
    if target.world_space do delta -= origin
    cosine, sine := math.cos(yaw_radians), math.sin(yaw_radians)
    local := third_person.Vec3 {
        delta.x * cosine + delta.z * sine,
        delta.y,
        -delta.x * sine + delta.z * cosine,
    }
    horizontal_length := f32(math.sqrt(f64(local.x * local.x + local.z * local.z)))
    if horizontal_length > .0001 {
        local.x /= horizontal_length
        local.z /= horizontal_length
    }
    local.y = clamp(local.y, -1, 1)
    return local, true
}

// Compose non-overlapping authored regions without flattening the base pose.
// A seated base can own lower body and hind paws while a wave supplies chest,
// head, ears, and forepaws. Deliberate ownership keeps blend semantics obvious
// and avoids silently summing two incompatible offsets on the same joint.
mouse_emote_pose_overlay :: proc(base, overlay: Mouse_Emote_Pose) -> Mouse_Emote_Pose {
    result := base
    if .Lower_Body in overlay.channels {
        result.bones[0] = overlay.bones[0]
        result.bones[1] = overlay.bones[1]
        result.body_height = overlay.body_height
        result.body_compression = overlay.body_compression
        result.channels += {.Lower_Body}
    }
    if .Upper_Body in overlay.channels {
        result.bones[2] = overlay.bones[2]
        result.bones[3] = overlay.bones[3]
        result.channels += {.Upper_Body}
    }
    if .Head in overlay.channels {
        result.bones[4] = overlay.bones[4]
        result.channels += {.Head}
    }
    if .Ears in overlay.channels {
        result.ears = overlay.ears
        result.channels += {.Ears}
    }
    if .Fore_Paws in overlay.channels {
        result.paws[0] = overlay.paws[0]
        result.paws[2] = overlay.paws[2]
        result.channels += {.Fore_Paws}
    }
    if .Hind_Paws in overlay.channels {
        result.paws[1] = overlay.paws[1]
        result.paws[3] = overlay.paws[3]
        result.channels += {.Hind_Paws}
    }
    if .Tail in overlay.channels {
        result.tail = overlay.tail
        result.channels += {.Tail}
    }
    if .Secondary in overlay.channels {
        result.breathing_weight = overlay.breathing_weight
        result.blink_weight = overlay.blink_weight
        result.idle_weight = overlay.idle_weight
        result.channels += {.Secondary}
    }
    return result
}

mouse_emote_set_phase :: proc(state: ^Mouse_Emote_State, phase: Mouse_Emote_Phase) {
    state.phase = phase
    state.phase_seconds = 0
}

mouse_emote_update :: proc(state: ^Mouse_Emote_State, inputs: Mouse_Emote_Inputs, delta_seconds: f32) {
    if !mouse_emote_active(state) || delta_seconds <= 0 do return
    if inputs.movement_intent > MOUSE_EMOTE_MOVEMENT_INTENT_CANCEL ||
        inputs.horizontal_speed > MOUSE_EMOTE_SPEED_CANCEL ||
        !inputs.grounded ||
        !inputs.player_controlled ||
        inputs.incompatible_pose ||
        inputs.paused {
        mouse_emote_cancel(state)
    }

    if state.scrub_enabled {
        state.normalized_time = clamp(state.scrub_normalized, 0, 1)
        state.blend_weight = 1
        return
    }
    if state.frozen do return

    delta := min(delta_seconds, f32(.1))
    state.elapsed_seconds += delta
    state.phase_seconds += delta
    switch state.phase {
    case .Anticipation:
        state.normalized_time = clamp(state.phase_seconds / MOUSE_EMOTE_ANTICIPATION_SECONDS * .16, 0, .16)
        state.blend_weight = mouse_emote_smoothstep(state.phase_seconds / MOUSE_EMOTE_ANTICIPATION_SECONDS)
        if state.phase_seconds >= MOUSE_EMOTE_ANTICIPATION_SECONDS do mouse_emote_set_phase(state, .Performance)
    case .Performance:
        state.normalized_time = .16 + clamp(state.phase_seconds / MOUSE_EMOTE_PERFORMANCE_SECONDS, 0, 1) * .64
        state.blend_weight = 1
        if state.phase_seconds >= MOUSE_EMOTE_PERFORMANCE_SECONDS {
            if state.loop_limit > state.loop_count + 1 {
                state.loop_count += 1
                mouse_emote_set_phase(state, .Performance)
            } else if state.loop_limit == 0 && (state.action == .Sit || state.action == .Pick_Up_Hold || state.action == .Sleep) {
                mouse_emote_set_phase(state, .Hold)
            } else {
                mouse_emote_set_phase(state, .Recovery)
            }
        }
    case .Hold:
        state.normalized_time = .80
        state.blend_weight = 1
    case .Recovery:
        state.normalized_time = .80 + clamp(state.phase_seconds / MOUSE_EMOTE_RECOVERY_SECONDS, 0, 1) * .20
        state.blend_weight = 1 - mouse_emote_smoothstep(state.phase_seconds / MOUSE_EMOTE_RECOVERY_SECONDS)
        if state.phase_seconds >= MOUSE_EMOTE_RECOVERY_SECONDS do mouse_emote_reset(state)
    case .Blend_Out:
        state.blend_weight = 1 - mouse_emote_smoothstep(state.phase_seconds / MOUSE_EMOTE_BLEND_OUT_SECONDS)
        if state.phase_seconds >= MOUSE_EMOTE_BLEND_OUT_SECONDS do mouse_emote_reset(state)
    case .Inactive:
    }
}

mouse_emote_pose :: proc(state: ^Mouse_Emote_State) -> Mouse_Emote_Pose {
    pose := Mouse_Emote_Pose{breathing_weight = 1, blink_weight = 1, idle_weight = 1}
    if !mouse_emote_active(state) || state.blend_weight <= 0 do return pose
    // The foundation's synthetic pose exercises every channel. Production
    // actions deliberately remain neutral until their individual todo owns
    // their motion design.
    if state.action != .Synthetic_Test do return pose

    phase := clamp(state.normalized_time, 0, 1)
    seed_bits := state.variation_seed * 1664525 + 1013904223
    variation := f32(seed_bits & 0xffff) / f32(0xffff) * 2 - 1
    pulse := math.sin(phase * math.TAU + variation * .08)
    weight := clamp(state.blend_weight, 0, 1)
    side := state.handedness == .Left ? f32(-1) : f32(1)
    pose.channels = {.Lower_Body, .Upper_Body, .Head, .Ears, .Fore_Paws, .Hind_Paws, .Tail, .Secondary}
    for index in 0 ..< len(pose.bones) {
        amount := f32(index + 1) / f32(len(pose.bones))
        pose.bones[index] = {
            position = {side * .018 * amount, .025 * amount, -.012 * amount},
            pitch    = .10 * amount,
            yaw      = side * (.055 + variation * .008) * amount,
            roll     = side * .075 * amount,
            weight   = weight,
        }
    }
    pose.ears[0] = {position = {-.018, .025, .012}, yaw = -.12, roll = -.08, weight = weight}
    pose.ears[1] = {position = {.018, -.010, -.008}, yaw = .16, roll = .10, weight = weight}
    pose.paws[0] = {local_offset = {side * .035, .22 + pulse * .025, -.05}, weight = weight, planted = false}
    pose.paws[1] = {local_offset = {0, .015, -.025}, weight = weight, planted = true}
    pose.paws[2] = {local_offset = {-side * .018, .07, .025}, weight = weight, planted = false}
    pose.paws[3] = {local_offset = {0, .015, -.025}, weight = weight, planted = true}
    pose.tail = {local_direction = {side * .42, .12, -1}, lift = .08, curl = side * .35, tip = -.18, weight = weight}
    pose.body_height = .035 * weight
    pose.body_compression = .018 * weight
    pose.breathing_weight = 1 - weight * .75
    pose.blink_weight = 1 - weight * .55
    pose.idle_weight = 1 - weight
    return pose
}

when ODIN_TEST {
    @(test)
    mouse_emote_names_round_trip :: proc(t: ^testing.T) {
        for action in Mouse_Emote {
            parsed, ok := mouse_emote_from_name(mouse_emote_name(action))
            testing.expect(t, ok)
            testing.expect_value(t, parsed, action)
        }
        _, unknown := mouse_emote_from_name("unknown")
        testing.expect(t, !unknown)
    }

    @(test)
    mouse_emote_progresses_loops_and_completes :: proc(t: ^testing.T) {
        state: Mouse_Emote_State
        testing.expect(t, mouse_emote_start(&state, .Wave, loop_limit = 2))
        inputs := Mouse_Emote_Inputs{grounded = true, player_controlled = true}
        for _ in 0 ..< 180 do mouse_emote_update(&state, inputs, 1.0 / 60.0)
        testing.expect_value(t, state.action, Mouse_Emote.None)
        testing.expect(t, state.playback_revision >= 2)
    }

    @(test)
    mouse_emote_movement_cancels_with_bounded_blend_out :: proc(t: ^testing.T) {
        state: Mouse_Emote_State
        _ = mouse_emote_start(&state, .Wave)
        still := Mouse_Emote_Inputs{grounded = true, player_controlled = true}
        mouse_emote_update(&state, still, .2)
        moving := still
        moving.movement_intent = 1
        mouse_emote_update(&state, moving, .01)
        testing.expect_value(t, state.phase, Mouse_Emote_Phase.Blend_Out)
        testing.expect(t, state.cancelling)
        for _ in 0 ..< 3 do mouse_emote_update(&state, moving, MOUSE_EMOTE_BLEND_OUT_SECONDS / 3)
        testing.expect_value(t, state.action, Mouse_Emote.None)
    }

    @(test)
    mouse_emote_replacement_and_scrub_are_deterministic :: proc(t: ^testing.T) {
        state: Mouse_Emote_State
        _ = mouse_emote_start(&state, .Wave, .Left, variation_seed = 7)
        first_revision := state.playback_revision
        _ = mouse_emote_start(&state, .Synthetic_Test, .Right, variation_seed = 11)
        testing.expect(t, state.playback_revision > first_revision)
        state.scrub_enabled = true
        state.scrub_normalized = .625
        mouse_emote_update(&state, {grounded = true, player_controlled = true}, 1)
        testing.expect_value(t, state.normalized_time, f32(.625))
        testing.expect_value(t, state.blend_weight, f32(1))
        first := mouse_emote_pose(&state)
        second := mouse_emote_pose(&state)
        testing.expect_value(t, first, second)
        testing.expect(t, first.bones[4].weight == 1)
        testing.expect(t, first.ears[0].weight == 1)
        testing.expect(t, first.paws[0].weight == 1)
        testing.expect(t, first.tail.weight == 1)
        testing.expect(t, .Lower_Body in first.channels)
        testing.expect(t, .Upper_Body in first.channels)
        testing.expect(t, .Head in first.channels)
        testing.expect(t, .Ears in first.channels)
        testing.expect(t, .Fore_Paws in first.channels)
        testing.expect(t, .Hind_Paws in first.channels)
        testing.expect(t, .Tail in first.channels)
        state.variation_seed = 12
        varied := mouse_emote_pose(&state)
        testing.expect(t, varied.bones[4].yaw != first.bones[4].yaw)
    }

    @(test)
    mouse_emote_inactive_pose_is_identity :: proc(t: ^testing.T) {
        pose := mouse_emote_pose(nil)
        testing.expect_value(t, pose.bones, [5]Mouse_Emote_Bone_Pose{})
        testing.expect_value(t, pose.ears, [2]Mouse_Emote_Ear_Pose{})
        testing.expect_value(t, pose.paws, [4]Mouse_Emote_Paw_Pose{})
        testing.expect_value(t, pose.tail, Mouse_Emote_Tail_Pose{})
        testing.expect_value(t, pose.breathing_weight, f32(1))
        testing.expect_value(t, pose.blink_weight, f32(1))
        testing.expect_value(t, pose.idle_weight, f32(1))
    }

    @(test)
    mouse_emote_target_converts_world_to_clamped_local_direction :: proc(t: ^testing.T) {
        local, ok := mouse_emote_target_local(
            {position = {12, 4, 20}, valid = true, world_space = true},
            {10, 2, 20},
            0,
        )
        testing.expect(t, ok)
        testing.expect(t, math.abs(local.x - 1) < .0001)
        testing.expect(t, math.abs(local.z) < .0001)
        testing.expect_value(t, local.y, f32(1))
        _, missing := mouse_emote_target_local({}, {}, 0)
        testing.expect(t, !missing)
    }

    @(test)
    mouse_emote_pose_overlay_preserves_seated_base_channels :: proc(t: ^testing.T) {
        base := Mouse_Emote_Pose {
            channels         = {.Lower_Body, .Hind_Paws},
            breathing_weight = 1,
            blink_weight     = 1,
            idle_weight      = 1,
        }
        base.bones[0] = {position = {0, -.2, 0}, weight = 1}
        base.paws[1] = {local_offset = {0, 0, .2}, weight = 1, planted = true}
        overlay := Mouse_Emote_Pose {
            channels         = {.Upper_Body, .Head, .Fore_Paws},
            breathing_weight = 1,
            blink_weight     = 1,
            idle_weight      = 1,
        }
        overlay.bones[2] = {pitch = .3, weight = 1}
        overlay.bones[4] = {yaw = -.2, weight = 1}
        overlay.paws[0] = {local_offset = {0, .3, 0}, weight = 1}
        combined := mouse_emote_pose_overlay(base, overlay)
        testing.expect_value(t, combined.bones[0], base.bones[0])
        testing.expect_value(t, combined.paws[1], base.paws[1])
        testing.expect_value(t, combined.bones[2], overlay.bones[2])
        testing.expect_value(t, combined.bones[4], overlay.bones[4])
        testing.expect_value(t, combined.paws[0], overlay.paws[0])
    }
}
