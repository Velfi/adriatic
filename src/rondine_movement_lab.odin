package main

import atmosphere "../packages/atmosphere"
import flight "../packages/flight"
import rondine_game "../packages/rondine"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import rl "zelda_engine:canvas2d"

RONDINE_MOVEMENT_LAB_COUNT :: 9
RONDINE_MOVEMENT_LAB_NAMES := [RONDINE_MOVEMENT_LAB_COUNT]string {
    "PLANING",
    "CARVE",
    "BREAKAWAY",
    "RIGHT DRIFT",
    "LEFT DRIFT",
    "RECOVERY",
    "COUNTERSTEER",
    "TOUCHDOWN",
    "LIFTOFF",
}
RONDINE_MOVEMENT_LAB_TARGETS := [RONDINE_MOVEMENT_LAB_COUNT]string {
    "planing",
    "carve",
    "breakaway",
    "drift",
    "counter-drift",
    "recovery",
    "countersteer",
    "touchdown",
    "liftoff",
}

rondine_movement_lab_runtimes: [RONDINE_MOVEMENT_LAB_COUNT]rondine_game.Runtime
rondine_movement_lab_focus: int

rondine_movement_lab_step :: proc(runtime: ^rondine_game.Runtime, frames: int, roll: f32) {
    for _ in 0 ..< frames {
        rondine_game.step(runtime, {throttle_up = true, roll = roll}, 0, 1.0 / 120.0)
    }
}

rondine_movement_lab_brake :: proc(runtime: ^rondine_game.Runtime, frames: int) {
    for _ in 0 ..< frames {
        rondine_game.step(runtime, {throttle_down = true}, 0, 1.0 / 120.0)
    }
}

rondine_movement_lab_brake_flick :: proc(runtime: ^rondine_game.Runtime, frames: int, roll: f32) {
    for _ in 0 ..< frames {
        rondine_game.step(runtime, {throttle_down = true, roll = roll}, 0, 1.0 / 120.0)
    }
}

rondine_movement_lab_switchback :: proc(runtime: ^rondine_game.Runtime) {
    rondine_movement_lab_step(runtime, 540, 1)
    for _ in 0 ..< 360 {
        rondine_game.step(runtime, {throttle_up = true, roll = -1}, 0, 1.0 / 120.0)
        if runtime.telemetry.drift_transition > .5 {
            // Let the whip open slightly while retaining a strong live pulse.
            rondine_movement_lab_step(runtime, 10, -1)
            return
        }
    }
}

rondine_movement_lab_rotate_y :: proc(vector: flight.Vec3, radians: f32) -> flight.Vec3 {
    cosine, sine := math.cos(radians), math.sin(radians)
    return {
        vector.x * cosine + vector.z * sine,
        vector.y,
        -vector.x * sine + vector.z * cosine,
    }
}

rondine_movement_lab_orient :: proc(runtime: ^rondine_game.Runtime, desired_forward: flight.Vec3) {
    if runtime == nil do return
    forward := runtime.body.basis.forward
    dot := forward.x * desired_forward.x + forward.z * desired_forward.z
    cross := forward.z * desired_forward.x - forward.x * desired_forward.z
    radians := math.atan2(cross, dot)
    center := runtime.body.position
    runtime.body.basis.forward = rondine_movement_lab_rotate_y(runtime.body.basis.forward, radians)
    runtime.body.basis.right = rondine_movement_lab_rotate_y(runtime.body.basis.right, radians)
    runtime.body.velocity = rondine_movement_lab_rotate_y(runtime.body.velocity, radians)
    for &sample in runtime.wake[:runtime.wake_count] {
        sample.position = center + rondine_movement_lab_rotate_y(sample.position - center, radians)
        sample.forward = rondine_movement_lab_rotate_y(sample.forward, radians)
        sample.right = rondine_movement_lab_rotate_y(sample.right, radians)
    }
}

rondine_movement_lab_place :: proc(runtime: ^rondine_game.Runtime, position: flight.Vec3) {
    delta := position - runtime.body.position
    runtime.body.position += delta
    runtime.vehicle.position = {runtime.body.position.x, runtime.body.position.y, runtime.body.position.z}
    for &sample in runtime.wake[:runtime.wake_count] do sample.position += delta
}

rondine_movement_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    rondine_movement_lab_focus = -1
    scar_focus := target == "scar"
    hookup_focus := target == "hookup"
    landing_focus := target == "landing" || target == "touchdown"
    liftoff_focus := target == "liftoff" || target == "release"
    detail_focus := target == "detail" || target == "wake-detail"
    far_detail_focus := target == "far-detail" || target == "drift-far-detail"
    night_detail_focus := target == "night-detail" || target == "drift-night-detail"
    launch_detail_focus := target == "launch-detail" || target == "surge-detail"
    cruise_detail_focus := target == "cruise-detail"
    brake_detail_focus := target == "brake-detail" || target == "decel-detail"
    brake_flick_focus := target == "brake-flick-detail" || target == "flick-detail"
    power_slide_focus := target == "power-slide-detail" || target == "power-over-detail"
    switchback_focus := target == "switchback-detail" || target == "transition-detail"
    switchback_scar_focus := target == "switchback-scar" || target == "transition-scar"
    wingtip_detail_focus := target == "wingtip-detail" || target == "wingtip-right-detail"
    wingtip_left_detail_focus := target == "wingtip-left-detail"
    trough_detail_focus := target == "trough-detail" || target == "aeration-detail"
    trough_far_detail_focus := target == "trough-far-detail" || target == "aeration-far-detail"
    counter_detail_focus := target == "counter-detail"
    counter_left_detail_focus := target == "counter-left-detail"
    planing_detail_focus := target == "planing-detail"
    carve_detail_focus := target == "carve-detail"
    carve_left_detail_focus := target == "carve-left-detail"
    left_detail_focus := target == "left-detail" || target == "counter-drift-detail"
    if scar_focus do rondine_movement_lab_focus = 2
    if hookup_focus do rondine_movement_lab_focus = 5
    if landing_focus do rondine_movement_lab_focus = 7
    if liftoff_focus do rondine_movement_lab_focus = 8
    if detail_focus do rondine_movement_lab_focus = 3
    if far_detail_focus do rondine_movement_lab_focus = 3
    if night_detail_focus do rondine_movement_lab_focus = 3
    if launch_detail_focus do rondine_movement_lab_focus = 0
    if cruise_detail_focus do rondine_movement_lab_focus = 0
    if brake_detail_focus do rondine_movement_lab_focus = 0
    if brake_flick_focus do rondine_movement_lab_focus = 0
    if power_slide_focus do rondine_movement_lab_focus = 3
    if switchback_focus do rondine_movement_lab_focus = 6
    if switchback_scar_focus do rondine_movement_lab_focus = 6
    if wingtip_detail_focus do rondine_movement_lab_focus = 3
    if wingtip_left_detail_focus do rondine_movement_lab_focus = 4
    if trough_detail_focus do rondine_movement_lab_focus = 0
    if trough_far_detail_focus do rondine_movement_lab_focus = 0
    if counter_detail_focus do rondine_movement_lab_focus = 6
    if counter_left_detail_focus do rondine_movement_lab_focus = 6
    if planing_detail_focus do rondine_movement_lab_focus = 0
    if carve_detail_focus do rondine_movement_lab_focus = 1
    if carve_left_detail_focus do rondine_movement_lab_focus = 1
    if left_detail_focus do rondine_movement_lab_focus = 4
    for name, index in RONDINE_MOVEMENT_LAB_TARGETS {
        if target == name || target == fmt.tprintf("%d", index) {
            rondine_movement_lab_focus = index
            break
        }
    }

    for &runtime, index in rondine_movement_lab_runtimes {
        runtime = rondine_game.new_runtime({0, rondine_game.GROUND_CLEARANCE, 0})
        runtime.tuning.takeoff_speed = 200
        switch index {
        case 0:
            planing_frames := launch_detail_focus ? 260 : 520
            if cruise_detail_focus do planing_frames = 1800
            rondine_movement_lab_step(&runtime, planing_frames, 0)
            if brake_detail_focus do rondine_movement_lab_brake(&runtime, 42)
            if brake_flick_focus do rondine_movement_lab_brake_flick(&runtime, 42, 1)
        case 1:
            carve_roll := carve_left_detail_focus ? f32(-.52) : f32(.52)
            rondine_movement_lab_step(&runtime, 620, carve_roll)
        case 2:
            rondine_movement_lab_step(&runtime, 520, 0)
            rondine_movement_lab_step(&runtime, 34, 1)
            if scar_focus do rondine_movement_lab_step(&runtime, 48, 1)
        case 3:
            if power_slide_focus {
                rondine_movement_lab_step(&runtime, 260, 0)
                rondine_movement_lab_step(&runtime, 72, 1)
            } else {
                rondine_movement_lab_step(&runtime, 720, 1)
            }
        case 4:
            rondine_movement_lab_step(&runtime, 720, -1)
        case 5:
            rondine_movement_lab_step(&runtime, 520, 1)
            rondine_movement_lab_step(&runtime, hookup_focus ? 34 : 240, 0)
        case 6:
            if switchback_focus || switchback_scar_focus {
                rondine_movement_lab_switchback(&runtime)
                if switchback_scar_focus do rondine_movement_lab_step(&runtime, 28, -1)
            } else {
                initial_roll := counter_left_detail_focus ? f32(-1) : f32(1)
                rondine_movement_lab_step(&runtime, 540, initial_roll)
                rondine_movement_lab_step(&runtime, 64, -initial_roll)
            }
        case 7:
            rondine_movement_lab_step(&runtime, 480, 0)
            runtime.body.position.y = rondine_game.GROUND_CLEARANCE + .2
            runtime.body.velocity.y = -8
            runtime.grounded = false
            runtime.wake_distance = 1.2
            rondine_game.step(&runtime, {throttle_up = true}, 0, .05)
            // Let the single touchdown marker expand enough to inspect its
            // broken ring while retaining a strong live impact readout.
            rondine_movement_lab_step(&runtime, 18, 0)
        case 8:
            // Build a long surface run, then lower the takeoff threshold for
            // one deterministic release. A few airborne frames separate the
            // aircraft from the fixed final-contact marker.
            rondine_movement_lab_step(&runtime, 480, 0)
            runtime.tuning.takeoff_speed = 22
            rondine_movement_lab_step(&runtime, 36, 0)
        }
        rondine_movement_lab_orient(&runtime, {0, 0, -1})
        overview_spacing := f32(14)
        overview_half_span :=
            f32(RONDINE_MOVEMENT_LAB_COUNT - 1) *
            overview_spacing *
            .5
        x := -overview_half_span + f32(index) * overview_spacing
        if rondine_movement_lab_focus >= 0 do x = 0
        rondine_movement_lab_place(&runtime, {x, rondine_game.GROUND_CLEARANCE, 0})
    }

    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = true
    editor.project.sea_level = 0
    atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 20)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    if night_detail_focus {
        atmosphere.set_world_minutes(&editor.atmosphere, 21 * 60 + 20)
    }
    editor.camera_pose = third_person.camera_look_at({0, 15, 43}, {0, 1, 0})
    if rondine_movement_lab_focus >= 0 {
        editor.camera_pose = third_person.camera_look_at({0, 9.5, 30}, {0, .5, 0})
    }
    if landing_focus {
        // Event markers lie almost flat on the ocean. A closer, steeper pose
        // exposes fragment winding and spacing that the long wake camera
        // intentionally compresses. Follow the fixed impact sample rather
        // than the aircraft, which continues moving after it touches down.
        marker := third_person.Vec3{0, .03, 0}
        strongest_impact: f32
        runtime := &rondine_movement_lab_runtimes[7]
        for sample in runtime.wake[:runtime.wake_count] {
            if sample.impact <= strongest_impact do continue
            strongest_impact = sample.impact
            marker = {sample.position.x, .03, sample.position.z}
        }
        editor.camera_pose =
            third_person.camera_look_at(
                marker + third_person.Vec3{0, 8.4, 9.6},
                marker,
            )
    }
    if liftoff_focus {
        marker := third_person.Vec3{0, .03, 0}
        strongest_release: f32
        runtime := &rondine_movement_lab_runtimes[8]
        for sample in runtime.wake[:runtime.wake_count] {
            if sample.release <= strongest_release do continue
            strongest_release = sample.release
            marker = {sample.position.x, .03, sample.position.z}
        }
        editor.camera_pose =
            third_person.camera_look_at(
                marker + third_person.Vec3{4.8, 7.5, 9.2},
                marker,
            )
    }
    if scar_focus {
        // The breakaway marker is fixed in the water while the Rondine keeps
        // moving. Center the camera on the strongest stored kick sample
        // instead of the aircraft, otherwise an aged scar leaves the frame
        // precisely when its expanding ring becomes easiest to inspect.
        marker := third_person.Vec3{0, .03, 0}
        strongest_kick: f32
        runtime := &rondine_movement_lab_runtimes[2]
        for sample in runtime.wake[:runtime.wake_count] {
            if sample.kick <= strongest_kick do continue
            strongest_kick = sample.kick
            marker = {sample.position.x, .03, sample.position.z}
        }
        editor.camera_pose =
            third_person.camera_look_at(
                marker + third_person.Vec3{0, 7.2, 8.2},
                marker,
            )
    }
    if hookup_focus {
        // Grip recovery is also stamped into the water and quickly falls
        // behind the aircraft. Follow the strongest stored hookup marker so
        // the converging zipper can be judged independently of the live clap.
        marker := third_person.Vec3{0, .03, 0}
        strongest_hookup: f32
        runtime := &rondine_movement_lab_runtimes[5]
        for sample in runtime.wake[:runtime.wake_count] {
            if sample.hookup <= strongest_hookup do continue
            strongest_hookup = sample.hookup
            marker = {sample.position.x, .03, sample.position.z}
        }
        editor.camera_pose =
            third_person.camera_look_at(
                marker + third_person.Vec3{5.5, 7.8, 8.8},
                marker,
            )
    }
    if switchback_scar_focus {
        marker := third_person.Vec3{0, .03, 0}
        strongest_transition: f32
        runtime := &rondine_movement_lab_runtimes[6]
        for sample in runtime.wake[:runtime.wake_count] {
            if sample.transition <= strongest_transition do continue
            strongest_transition = sample.transition
            marker = {sample.position.x, .03, sample.position.z}
        }
        editor.camera_pose =
            third_person.camera_look_at(
                marker + third_person.Vec3{5.8, 7.8, 9.2},
                marker,
            )
    }
    if detail_focus ||
       night_detail_focus ||
       launch_detail_focus ||
       cruise_detail_focus ||
       brake_detail_focus ||
       brake_flick_focus ||
       power_slide_focus ||
       switchback_focus ||
       wingtip_detail_focus ||
       wingtip_left_detail_focus ||
       trough_detail_focus ||
       counter_detail_focus ||
       counter_left_detail_focus ||
       planing_detail_focus ||
       carve_detail_focus ||
       carve_left_detail_focus ||
       left_detail_focus {
        // This pose deliberately gives up the complete trail silhouette to
        // make individual foam packets, transverse crests, droplets, and
        // surface chips large enough for screenshot-level visual QA.
        editor.camera_pose = third_person.camera_look_at({0, 10.5, 17}, {0, .15, 2.8})
    }
    if far_detail_focus {
        // A long chase view exposes the intended LOD ordering: droplets and
        // chips should retire before the broad trough and loaded wake wall.
        editor.camera_pose =
            third_person.camera_look_at(
                {0, 18.5, 48},
                {0, .25, -2},
            )
    }
    if power_slide_focus {
        // Power-over spray rises and moves laterally; the standard centered
        // wake camera collapses that height into the stern. Inspect from the
        // unloaded quarter so the outside sheet, ribs, and droplet crown
        // remain separately readable.
        editor.camera_pose =
            third_person.camera_look_at(
                {10.5, 8.8, 18.5},
                {0, .55, 2.4},
            )
    }
    if wingtip_detail_focus || wingtip_left_detail_focus {
        // View from the unloaded quarter so the low loaded wingtip and its
        // outboard spray sheet remain clear of the fuselage silhouette.
        camera_side := wingtip_left_detail_focus ? f32(-1) : f32(1)
        editor.camera_pose =
            third_person.camera_look_at(
                {camera_side * 11.2, 7.6, 18.2},
                {camera_side * 1.1, .48, 2.5},
            )
    }
    if trough_detail_focus {
        editor.camera_pose =
            third_person.camera_look_at(
                {0, 5.8, 15.5},
                {0, .08, 6.0},
            )
    }
    if trough_far_detail_focus {
        editor.camera_pose =
            third_person.camera_look_at(
                {0, 18.5, 48},
                {0, .20, -2},
            )
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

world_rondine_movement_lab :: proc(editor: ^Editor) {
    if editor == nil do return
    saved := editor.rondine
    saved_visible := editor.rondine_visible
    world_ocean(editor)
    for &runtime, index in rondine_movement_lab_runtimes {
        if rondine_movement_lab_focus >= 0 && index != rondine_movement_lab_focus do continue
        editor.rondine = runtime
        editor.rondine_visible = true
        world_rondine(editor)
        world_rondine_wake_fans(editor)
    }
    editor.rondine = saved
    editor.rondine_visible = saved_visible
}

rondine_movement_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel_width := min(f32(width) - 32, f32(980))
    focused := rondine_movement_lab_focus >= 0
    panel_height := focused ? f32(82) : f32(94)
    left := f32(width) * .5 - panel_width * .5
    top := f32(height) - panel_height - 16
    rl.DrawRectangleRounded({left, top, panel_width, panel_height}, .18, 6, {10, 25, 27, 238})
    columns := focused ? 1 : RONDINE_MOVEMENT_LAB_COUNT
    column_width := panel_width / f32(columns)
    draw_index := 0
    for runtime, index in rondine_movement_lab_runtimes {
        if rondine_movement_lab_focus >= 0 && index != rondine_movement_lab_focus do continue
        x := left + column_width * (f32(draw_index) + .5)
        name := RONDINE_MOVEMENT_LAB_NAMES[index]
        name_c := fmt.ctprintf("%s", name)
        name_size := rl.MeasureTextEx(rl.Font{}, name_c, 11, .8)
        rl.DrawTextEx(rl.Font{}, name_c, {x - name_size.x * .5, top + 18}, 11, .8, {226, 249, 243, 255})
        if focused {
            values := fmt.ctprintf(
                "%.0fm/s A%+.1f U%.0f B%.0f W%.0f S%+.0f D%.0f C%.0f K%.0f H%.0f I%.0f R%.0f Y%.1f G%d",
                runtime.telemetry.speed,
                runtime.telemetry.acceleration,
                runtime.telemetry.surge_intensity * 100,
                runtime.telemetry.brake_intensity * 100,
                runtime.telemetry.drift_transition * 100,
                runtime.telemetry.slip * 100,
                runtime.telemetry.drift_intensity * 100,
                runtime.telemetry.countersteer * 100,
                runtime.telemetry.drift_kick * 100,
                runtime.telemetry.hookup_kick * 100,
                runtime.telemetry.surface_impact * 100,
                runtime.telemetry.surface_release * 100,
                runtime.telemetry.height,
                runtime.grounded ? 1 : 0,
            )
            value_size := rl.MeasureTextEx(rl.Font{}, values, 10, .3)
            rl.DrawTextEx(rl.Font{}, values, {x - value_size.x * .5, top + 46}, 10, .3, {213, 194, 142, 255})
        } else {
            motion_values := fmt.ctprintf(
                "%.0fm/s S%+.0f D%.0f C%.0f",
                runtime.telemetry.speed,
                runtime.telemetry.slip * 100,
                runtime.telemetry.drift_intensity * 100,
                runtime.telemetry.countersteer * 100,
            )
            event_values := fmt.ctprintf(
                "K%.0f H%.0f I%.0f R%.0f",
                runtime.telemetry.drift_kick * 100,
                runtime.telemetry.hookup_kick * 100,
                runtime.telemetry.surface_impact * 100,
                runtime.telemetry.surface_release * 100,
            )
            motion_size := rl.MeasureTextEx(rl.Font{}, motion_values, 8, .15)
            event_size := rl.MeasureTextEx(rl.Font{}, event_values, 8, .15)
            rl.DrawTextEx(
                rl.Font{},
                motion_values,
                {x - motion_size.x * .5, top + 43},
                8,
                .15,
                {213, 194, 142, 255},
            )
            rl.DrawTextEx(
                rl.Font{},
                event_values,
                {x - event_size.x * .5, top + 62},
                8,
                .15,
                {183, 219, 211, 255},
            )
        }
        draw_index += 1
    }
}
