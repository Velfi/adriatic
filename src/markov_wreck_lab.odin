package main

import atmosphere "../packages/atmosphere"
import chase_camera "../packages/chase_camera"
import flight "../packages/flight"
import markov "../packages/markov"
import postale_game "../packages/postale"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strconv"
import sdl "vendor:sdl3"
import rl "zelda_engine:canvas2d"

MARKOV_WRECK_LENGTH :: 31
MARKOV_WRECK_CELL :: f32(11)
MARKOV_WRECK_DEFAULT_SEED :: u32(0x57524543)
MARKOV_WRECK_WATERLINE :: f32(0)
// Sink the hull through the ocean surface: the weather deck remains exposed,
// while the keel and lower bilges are visibly claimed by the sea.
MARKOV_WRECK_HULL_CENTER_Y :: f32(12)
// Route generation does not have an aircraft pose, so it uses a conservative
// fuselage clearance. Runtime collision uses the transformed Postale mesh.
MARKOV_WRECK_ROUTE_CLEARANCE_RADIUS :: f32(1.5)
MARKOV_WRECK_POSTALE_BROADPHASE_RADIUS :: f32(4.4)
WRECK_INSTANCE_CAPACITY :: 8

Markov_Wreck_Cell :: enum u8 {
    Empty,
    Spine,
    Fracture,
}

markov_wreck_cells: [MARKOV_WRECK_LENGTH]Markov_Wreck_Cell
markov_wreck_seed := MARKOV_WRECK_DEFAULT_SEED
markov_wreck_requested_seed := MARKOV_WRECK_DEFAULT_SEED

Markov_Wreck_Form :: enum {
    Liner,
    Dreadnought,
    Carrier,
}

markov_wreck_form: Markov_Wreck_Form
markov_wreck_break_index: int
markov_wreck_second_break_index: int
markov_wreck_part_count: int
markov_wreck_first_bay: int
markov_wreck_last_bay: int

Markov_Wreck_Part_State :: struct {
    first_bay:        int,
    last_bay:         int,
    offset_y:         f32,
    offset_z:         f32,
    roll:             f32,
    velocity_y:       f32,
    velocity_z:       f32,
    angular_velocity: f32,
}

markov_wreck_parts: [3]Markov_Wreck_Part_State

Markov_Wreck_Quality :: struct {
    occupied_bays:          int,
    fracture_bays:          int,
    obstacle_bays:          int,
    side_entry_bays:        int,
    debris_trails:          int,
    longest_fracture_chain: int,
    traversal_score:        f32,
    valid:                  bool,
}

markov_wreck_quality: Markov_Wreck_Quality

Markov_Wreck_Route_Quality :: struct {
    bays_evaluated:       int,
    navigable_bays:       int,
    centerline_obstacles: int,
    minimum_clear_routes: int,
    valid:                bool,
}

markov_wreck_route_quality: Markov_Wreck_Route_Quality

MARKOV_WRECK_COLLIDER_CAPACITY :: 1024

Markov_Wreck_Collider :: struct {
    a, b:   third_person.Vec3,
    radius: f32,
}

markov_wreck_colliders: [MARKOV_WRECK_COLLIDER_CAPACITY]Markov_Wreck_Collider
markov_wreck_collider_count: int
markov_wreck_postale_spawned: bool
markov_wreck_collision_verified: bool
markov_wreck_render_origin_x: f32
markov_wreck_render_origin_z: f32
markov_wreck_render_yaw: f32
markov_wreck_render_scale: f32 = 1
markov_wreck_authored_render: bool

Wreck_Instance :: struct {
    cells:              [MARKOV_WRECK_LENGTH]Markov_Wreck_Cell,
    seed:               u32,
    form:               Markov_Wreck_Form,
    break_index:        int,
    second_break_index: int,
    part_count:         int,
    first_bay:          int,
    last_bay:           int,
    parts:              [3]Markov_Wreck_Part_State,
    quality:            Markov_Wreck_Quality,
    origin_x:           f32,
    origin_z:           f32,
    yaw:                f32,
    scale:              f32,
}

markov_wreck_instance_capture :: proc(origin_x, origin_z, yaw: f32, scale: f32 = 1) -> Wreck_Instance {
    return {
        cells = markov_wreck_cells,
        seed = markov_wreck_seed,
        form = markov_wreck_form,
        break_index = markov_wreck_break_index,
        second_break_index = markov_wreck_second_break_index,
        part_count = markov_wreck_part_count,
        first_bay = markov_wreck_first_bay,
        last_bay = markov_wreck_last_bay,
        parts = markov_wreck_parts,
        quality = markov_wreck_quality,
        origin_x = origin_x,
        origin_z = origin_z,
        yaw = yaw,
        scale = scale,
    }
}

markov_wreck_instance_load :: proc(instance: ^Wreck_Instance) {
    if instance == nil do return
    markov_wreck_cells = instance.cells
    markov_wreck_seed = instance.seed
    markov_wreck_form = instance.form
    markov_wreck_break_index = instance.break_index
    markov_wreck_second_break_index = instance.second_break_index
    markov_wreck_part_count = instance.part_count
    markov_wreck_first_bay = instance.first_bay
    markov_wreck_last_bay = instance.last_bay
    markov_wreck_parts = instance.parts
    markov_wreck_quality = instance.quality
    markov_wreck_render_origin_x = instance.origin_x
    markov_wreck_render_origin_z = instance.origin_z
    markov_wreck_render_yaw = instance.yaw
    markov_wreck_render_scale = instance.scale
}

markov_wreck_transform_xz :: proc(local_x, local_z: f32) -> (f32, f32) {
    cosine, sine := math.cos(markov_wreck_render_yaw), math.sin(markov_wreck_render_yaw)
    x := local_x * markov_wreck_render_scale
    z := local_z * markov_wreck_render_scale
    return markov_wreck_render_origin_x + x * cosine - z * sine, markov_wreck_render_origin_z + x * sine + z * cosine
}

markov_wreck_hash :: proc(value: u32) -> u32 {
    x := value
    x = x ~ (x >> 16)
    x *= 0x7feb352d
    x = x ~ (x >> 15)
    x *= 0x846ca68b
    x = x ~ (x >> 16)
    return x
}

markov_wreck_random :: proc(value: u32) -> f32 {
    return f32(markov_wreck_hash(value) & 0x00ffffff) / f32(0x01000000)
}

markov_wreck_select_break :: proc(seed: u32) {
    center := (MARKOV_WRECK_LENGTH - 1) / 2
    markov_wreck_break_index = center
    best_score := 0x7fffffff
    for cell, index in markov_wreck_cells {
        if cell != .Fracture || index < 7 || index > MARKOV_WRECK_LENGTH - 8 do continue
        jitter := int(markov_wreck_hash(seed ~ u32(index * 0x7f4a)) % 5)
        score := abs(index - center) * 5 + jitter
        if score < best_score {
            best_score = score
            markov_wreck_break_index = index
        }
    }
    markov_wreck_second_break_index = -1
    markov_wreck_part_count = 2
    // Most seeds split into three major masses. The second wound must be far
    // enough from the first to leave a recognizable ship section between.
    if markov_wreck_hash(seed ~ 0x3f12ac7) % 100 < 62 {
        second_score := 0x7fffffff
        for cell, index in markov_wreck_cells {
            if cell != .Fracture ||
               index < 6 ||
               index > MARKOV_WRECK_LENGTH - 7 ||
               abs(index - markov_wreck_break_index) < 6 {
                continue
            }
            separation_target := 9
            score :=
                abs(abs(index - markov_wreck_break_index) - separation_target) * 7 +
                int(markov_wreck_hash(seed ~ u32(index * 0x91e1)) % 9)
            if score < second_score {
                second_score = score
                markov_wreck_second_break_index = index
            }
        }
        if markov_wreck_second_break_index >= 0 {
            markov_wreck_part_count = 3
            if markov_wreck_second_break_index < markov_wreck_break_index {
                earlier := markov_wreck_second_break_index
                markov_wreck_second_break_index = markov_wreck_break_index
                markov_wreck_break_index = earlier
            }
        }
    }
    markov_wreck_settle_parts(seed)
}

markov_wreck_part_for_bay :: proc(x_index: int) -> int {
    for part_index in 0 ..< markov_wreck_part_count {
        part := &markov_wreck_parts[part_index]
        if x_index >= part.first_bay && x_index <= part.last_bay do return part_index
    }
    return 0
}

markov_wreck_settle_parts :: proc(seed: u32) {
    markov_wreck_parts = {}
    boundaries := [4]int {
        markov_wreck_first_bay,
        markov_wreck_break_index + 1,
        markov_wreck_second_break_index >= 0 ? markov_wreck_second_break_index + 1 : markov_wreck_last_bay + 1,
        markov_wreck_last_bay + 1,
    }
    for part_index in 0 ..< markov_wreck_part_count {
        part := &markov_wreck_parts[part_index]
        part.first_bay = boundaries[part_index]
        part.last_bay = boundaries[part_index + 1] - 1
        salt := u32(part_index) * 0x6d2b79f5
        part.velocity_y = (markov_wreck_random(seed ~ 0x8711 ~ salt) - .5) * 1.8
        part.velocity_z = (markov_wreck_random(seed ~ 0x8712 ~ salt) - .5) * 4
        part.angular_velocity = (markov_wreck_random(seed ~ 0x8713 ~ salt) - .5) * .09
    }

    // A small deterministic rigid-body relaxation. Water buoyancy pulls each
    // mass toward a damage/length-dependent draft while drag damps motion.
    // Adjacent severed masses receive opposing lateral drift targets so they
    // settle with readable open-water wounds instead of overlapping.
    DT :: f32(.12)
    for _ in 0 ..< 48 {
        for part_index in 0 ..< markov_wreck_part_count {
            part := &markov_wreck_parts[part_index]
            length_bays := max(part.last_bay - part.first_bay + 1, 1)
            short_section_sink := clamp(f32(9 - length_bays) * .32, f32(0), f32(2.4))
            target_y := part_index == 0 ? f32(0) : -(2.4 + f32(part_index) * .9 + short_section_sink)
            salt := u32(part_index) * 0x9e3779b9
            direction := markov_wreck_hash(seed ~ 0x57e7 ~ salt) & 1 == 0 ? f32(-1) : f32(1)
            target_z := f32(0)
            target_roll := f32(0)
            if part_index > 0 {
                target_z = direction * (11 + f32(part_index) * 5 + markov_wreck_random(seed ~ 0x57e8 ~ salt) * 5)
                target_roll =
                    direction * (.08 + f32(part_index) * .025 + markov_wreck_random(seed ~ 0x57e9 ~ salt) * .08)
                if markov_wreck_form == .Carrier do target_roll *= .56
            }
            acceleration_y := (target_y - part.offset_y) * 3.2 - part.velocity_y * 2.4
            acceleration_z := (target_z - part.offset_z) * 2.5 - part.velocity_z * 2.1
            angular_acceleration := (target_roll - part.roll) * 3.4 - part.angular_velocity * 2.5
            part.velocity_y += acceleration_y * DT
            part.velocity_z += acceleration_z * DT
            part.angular_velocity += angular_acceleration * DT
            part.offset_y += part.velocity_y * DT
            part.offset_z += part.velocity_z * DT
            part.roll += part.angular_velocity * DT
        }
    }
}

markov_wreck_update_bounds :: proc() {
    markov_wreck_first_bay = MARKOV_WRECK_LENGTH
    markov_wreck_last_bay = -1
    for cell, index in markov_wreck_cells {
        if cell == .Empty do continue
        markov_wreck_first_bay = min(markov_wreck_first_bay, index)
        markov_wreck_last_bay = max(markov_wreck_last_bay, index)
    }
}

markov_wreck_major_break_after :: proc(x_index: int) -> bool {
    return(
        x_index == markov_wreck_break_index ||
        (markov_wreck_second_break_index >= 0 && x_index == markov_wreck_second_break_index) \
    )
}

markov_wreck_ring_center :: proc(x_index: int) -> third_person.Vec3 {
    center := f32(MARKOV_WRECK_LENGTH - 1) * .5
    x, z := markov_wreck_transform_xz((f32(x_index) - center) * MARKOV_WRECK_CELL, 0)
    result := third_person.Vec3{x, MARKOV_WRECK_HULL_CENTER_Y, z}
    part := &markov_wreck_parts[markov_wreck_part_for_bay(x_index)]
    result.y += part.offset_y * markov_wreck_render_scale
    result.x -= math.sin(markov_wreck_render_yaw) * part.offset_z * markov_wreck_render_scale
    result.z += math.cos(markov_wreck_render_yaw) * part.offset_z * markov_wreck_render_scale
    return result
}

markov_wreck_model :: proc() -> markov.Proc_Node {
    empty := int(Markov_Wreck_Cell.Empty)
    spine := int(Markov_Wreck_Cell.Spine)
    fracture := int(Markov_Wreck_Cell.Fracture)
    return markov.node(
        markov.Proc_Tag.sequence,
        []markov.Proc_Attr{markov.kattr(.values, markov.values_count(3)), markov.kattr(.origin, true)},
        []markov.Proc_Node {
            // Grow an asymmetric keel in both directions from the origin.
            markov.node(
                markov.Proc_Tag.one,
                []markov.Proc_Attr {
                    markov.kattr(
                        .in_,
                        markov.match_layer(
                            markov.match_row(markov.one_of(markov.sym(spine)), markov.one_of(markov.sym(empty))),
                        ),
                    ),
                    markov.kattr(.out, markov.write_layer(markov.write_row(markov.keep(), markov.sym(spine)))),
                    markov.kattr(.steps, 14),
                },
            ),
            markov.node(
                markov.Proc_Tag.one,
                []markov.Proc_Attr {
                    markov.kattr(
                        .in_,
                        markov.match_layer(
                            markov.match_row(markov.one_of(markov.sym(empty)), markov.one_of(markov.sym(spine))),
                        ),
                    ),
                    markov.kattr(.out, markov.write_layer(markov.write_row(markov.sym(spine), markov.keep()))),
                    markov.kattr(.steps, 12),
                },
            ),
            // Fractures become missing or twisted hull frames during rendering.
            markov.node(
                markov.Proc_Tag.one,
                []markov.Proc_Attr {
                    markov.kattr(.in_, markov.match_layer(markov.match_row(markov.one_of(markov.sym(spine))))),
                    markov.kattr(.out, markov.write_layer(markov.write_row(markov.sym(fracture)))),
                    markov.kattr(.steps, 6),
                },
            ),
        },
    )
}

markov_wreck_generate_instance :: proc(
    requested_seed: u32,
    origin_x, origin_z, yaw: f32,
    scale: f32 = 1,
) -> (
    Wreck_Instance,
    bool,
) {
    markov_wreck_form = Markov_Wreck_Form(markov_wreck_hash(requested_seed) % 3)
    for attempt in 0 ..< 16 {
        candidate_seed := requested_seed + u32(attempt) * 0x9e3779b9
        model := markov_wreck_model()
        ip, loaded := markov.load_model_proc(model, {MARKOV_WRECK_LENGTH, 1, 1})
        if !loaded do continue
        frames := markov.run(ip, int(candidate_seed), 0, false, context.temp_allocator)
        accepted := false
        if len(frames) > 0 {
            final := &frames[len(frames) - 1]
            for index in 0 ..< MARKOV_WRECK_LENGTH {
                markov_wreck_cells[index] = Markov_Wreck_Cell(final.state[index])
            }
            markov_wreck_update_bounds()
            quality := markov_wreck_evaluate(candidate_seed)
            if quality.valid {
                markov_wreck_seed = candidate_seed
                markov_wreck_quality = quality
                markov_wreck_select_break(candidate_seed)
                markov_wreck_build_colliders()
                route_quality := markov_wreck_evaluate_routes()
                accepted = route_quality.valid
                if accepted do markov_wreck_route_quality = route_quality
            }
        }
        markov.interpreter_destroy(ip)
        if accepted {
            return markov_wreck_instance_capture(origin_x, origin_z, yaw, scale), true
        }
    }
    return {}, false
}

markov_wreck_evaluate :: proc(seed: u32) -> Markov_Wreck_Quality {
    result: Markov_Wreck_Quality
    fracture_chain := 0
    for cell, index in markov_wreck_cells {
        if cell == .Empty {
            fracture_chain = 0
            continue
        }
        result.occupied_bays += 1
        if index % 8 < 3 do result.side_entry_bays += 1
        if cell == .Fracture {
            result.fracture_bays += 1
            result.obstacle_bays += 1
            fracture_chain += 1
            result.longest_fracture_chain = max(result.longest_fracture_chain, fracture_chain)
            ring_seed := seed ~ u32(index * 0x9e37)
            if markov_wreck_hash(ring_seed ~ 0xdeb715) & 1 == 0 do result.debris_trails += 1
        } else {
            fracture_chain = 0
        }
    }
    route_density := f32(result.obstacle_bays) / f32(max(result.occupied_bays, 1))
    entry_density := f32(result.side_entry_bays) / f32(max(result.occupied_bays, 1))
    chain_penalty := f32(max(result.longest_fracture_chain - 2, 0)) * .18
    result.traversal_score = clamp(
        .48 + min(route_density, f32(.25)) * 1.15 + min(entry_density, f32(.4)) * .45 - chain_penalty,
        f32(0),
        f32(1),
    )
    result.valid =
        result.occupied_bays >= 25 &&
        result.fracture_bays >= 4 &&
        result.fracture_bays <= 7 &&
        result.obstacle_bays >= 4 &&
        result.side_entry_bays >= 7 &&
        result.longest_fracture_chain <= 2 &&
        result.traversal_score >= .72
    return result
}

markov_wreck_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    auto_spawn := false
    auto_crash := false
    auto_randomize := false
    seed_target := target
    FLIGHT_PREFIX :: "flight-"
    CRASH_PREFIX :: "crash-"
    RANDOMIZE_PREFIX :: "randomize-"
    if len(seed_target) > len(FLIGHT_PREFIX) && seed_target[:len(FLIGHT_PREFIX)] == FLIGHT_PREFIX {
        auto_spawn = true
        seed_target = seed_target[len(FLIGHT_PREFIX):]
    } else if len(seed_target) > len(CRASH_PREFIX) && seed_target[:len(CRASH_PREFIX)] == CRASH_PREFIX {
        auto_spawn = true
        auto_crash = true
        seed_target = seed_target[len(CRASH_PREFIX):]
    } else if len(seed_target) > len(RANDOMIZE_PREFIX) && seed_target[:len(RANDOMIZE_PREFIX)] == RANDOMIZE_PREFIX {
        auto_randomize = true
        seed_target = seed_target[len(RANDOMIZE_PREFIX):]
    }
    markov_wreck_requested_seed = MARKOV_WRECK_DEFAULT_SEED
    if parsed, ok := strconv.parse_int(seed_target); ok && parsed >= 0 && parsed <= 0xffffffff {
        markov_wreck_requested_seed = u32(parsed)
    }
    markov_wreck_form = Markov_Wreck_Form(markov_wreck_hash(markov_wreck_requested_seed) % 3)
    generated := false
    for attempt in 0 ..< 16 {
        candidate_seed := markov_wreck_requested_seed + u32(attempt) * 0x9e3779b9
        model := markov_wreck_model()
        ip, loaded := markov.load_model_proc(model, {MARKOV_WRECK_LENGTH, 1, 1})
        if !loaded do continue
        frames := markov.run(ip, int(candidate_seed), 0, false, context.temp_allocator)
        if len(frames) > 0 {
            final := &frames[len(frames) - 1]
            for index in 0 ..< MARKOV_WRECK_LENGTH {
                markov_wreck_cells[index] = Markov_Wreck_Cell(final.state[index])
            }
            markov_wreck_update_bounds()
            quality := markov_wreck_evaluate(candidate_seed)
            if quality.valid {
                markov_wreck_seed = candidate_seed
                markov_wreck_quality = quality
                markov_wreck_select_break(candidate_seed)
                markov_wreck_build_colliders()
                route_quality := markov_wreck_evaluate_routes()
                if route_quality.valid {
                    markov_wreck_route_quality = route_quality
                    generated = true
                    fmt.println(
                        "markov wreck accepted:",
                        candidate_seed,
                        "parts",
                        markov_wreck_part_count,
                        "breaks",
                        markov_wreck_break_index,
                        markov_wreck_second_break_index,
                    )
                } else {
                    fmt.println(
                        "markov wreck route rejected:",
                        candidate_seed,
                        route_quality.bays_evaluated,
                        route_quality.navigable_bays,
                        route_quality.centerline_obstacles,
                        route_quality.minimum_clear_routes,
                    )
                }
            }
        }
        markov.interpreter_destroy(ip)
        if generated do break
    }
    if !generated do return false
    markov_wreck_postale_spawned = false
    markov_wreck_collision_verified = false

    editor.camera_pose = third_person.camera_look_at({170, 82, 185}, {0, 24, 0})
    editor.editor_focus = {0, 24, 0}
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    editor.capture_world_only = true
    atmosphere.set_world_minutes(&editor.atmosphere, 17 * 60 + 20)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    if auto_randomize do return markov_wreck_randomize(editor)
    if auto_spawn {
        if !markov_wreck_spawn_postale(editor) do return false
        if auto_crash {
            if markov_wreck_collider_count == 0 do return false
            probe := markov_wreck_colliders[0].a
            editor.postale.body.position = {probe.x, probe.y, probe.z}
            editor.postale.body.velocity = editor.postale.body.basis.forward * 46
            editor.postale.vehicle.position = probe
            markov_wreck_collision_verified = markov_wreck_aircraft_collision_step(editor)
            if !markov_wreck_collision_verified || !editor.postale.crashed || editor.postale.structural_damage < 1 {
                return false
            }
        }
    }
    return true
}

markov_wreck_spawn_postale :: proc(editor: ^Editor) -> bool {
    if editor == nil || !lab_scene_is_active(editor, "markov-wreck") do return false
    if editor.pilot.mode == .Driving {
        _ = vehicles.try_exit(&editor.pilot, true)
    }
    if !vehicles.aircraft_fleet_unlock(&editor.aircraft, .Postale) ||
       !vehicles.aircraft_fleet_switch(&editor.aircraft, .Postale) {
        return false
    }

    // The wreck's keel runs along X. Spawn beyond the intact stern and point
    // down the torn hold or hangar, leaving several seconds to read the first gate.
    approach_center := markov_wreck_ring_center(markov_wreck_last_bay)
    spawn := flight.Vec3{238, approach_center.y + 2, approach_center.z}
    aim := markov_wreck_ring_center(markov_wreck_break_index)
    forward := flight.Vec3{aim.x - spawn.x, aim.y - spawn.y, aim.z - spawn.z}
    forward_length := max(linalg.length(forward), f32(.001))
    forward *= 1 / forward_length
    right := flight.Vec3{-forward.z, 0, forward.x}
    right_length := max(linalg.length(right), f32(.001))
    right *= 1 / right_length
    up := flight.Vec3 {
        right.y * forward.z - right.z * forward.y,
        right.z * forward.x - right.x * forward.z,
        right.x * forward.y - right.y * forward.x,
    }
    basis := flight.Basis {
        forward = forward,
        up      = up,
        right   = right,
    }
    editor.postale.spawn_position = spawn
    editor.postale.spawn_basis = basis
    markov_wreck_reset_postale(editor)
    editor.postale_visible = true
    editor.libellula_visible = false

    editor.in_map = true
    editor.map_time = f32(rl.GetTime())
    editor.aircraft_fixed_accumulator = 0
    editor.aircraft_previous_body_valid = false
    editor.capture_world_only = false
    markov_wreck_postale_spawned = true
    if !markov_wreck_ensure_flight_control(editor) {
        markov_wreck_postale_spawned = false
        return false
    }
    chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
    editor.camera_pose = editor.flight_camera.pose
    third_person.camera_set_pose(&editor.cameras, .Player, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Player)
    set_pointer_locked(true)
    _ = sdl.HideCursor()
    return true
}

// A wreck flight is a self-contained challenge, not an ordinary enter/exit
// interaction. Keep its ownership state authoritative for the whole session:
// hot reloads and lab transitions can preserve the visible aircraft while
// invalidating one of the driver pointers, which makes driving_aircraft false
// and silently routes all input away from the flight model.
markov_wreck_ensure_flight_control :: proc(editor: ^Editor) -> bool {
    if editor == nil || !lab_scene_is_active(editor, "markov-wreck") || !markov_wreck_postale_spawned {
        return false
    }
    if !vehicles.aircraft_fleet_switch(&editor.aircraft, .Postale) do return false

    if editor.pilot.vehicle != nil && editor.pilot.vehicle != &editor.postale.vehicle {
        editor.pilot.vehicle.driver = nil
    }
    if editor.postale.vehicle.driver != nil && editor.postale.vehicle.driver != &editor.pilot {
        editor.postale.vehicle.driver.vehicle = nil
        editor.postale.vehicle.driver.mode = .On_Foot
    }
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = true
    editor.libellula_visible = false
    editor.pilot.mode = .Driving
    editor.pilot.vehicle = &editor.postale.vehicle
    editor.postale.vehicle.driver = &editor.pilot
    vehicles.sync_driver(&editor.pilot)
    return true
}

markov_wreck_reset_postale :: proc(editor: ^Editor) -> bool {
    if editor == nil || !lab_scene_is_active(editor, "markov-wreck") do return false
    spawn := editor.postale.spawn_position
    basis := editor.postale.spawn_basis
    postale_game.reset(&editor.postale, 0)
    editor.postale.body.position = spawn
    editor.postale.body.basis = basis
    editor.postale.body.velocity = basis.forward * 46
    editor.postale.vehicle.position = {spawn.x, spawn.y, spawn.z}
    editor.postale.vehicle.yaw_radians = postale_game.yaw_radians(basis)
    editor.postale.vehicle.locked = false
    editor.postale.grounded = false
    editor.postale.was_grounded = false
    editor.postale.throttle = .76
    editor.aircraft_fixed_accumulator = 0
    editor.aircraft_previous_body_valid = false
    chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
    editor.camera_pose = editor.flight_camera.pose
    vehicles.sync_driver(&editor.pilot)
    return true
}

markov_wreck_spawn_button_bounds :: proc(height: i32) -> rl.Rectangle {
    return {32, f32(height) - 78, 238, 46}
}

markov_wreck_randomize_button_bounds :: proc(height: i32) -> rl.Rectangle {
    return {282, f32(height) - 78, 238, 46}
}

markov_wreck_randomize :: proc(editor: ^Editor) -> bool {
    if editor == nil || markov_wreck_postale_spawned do return false
    next_seed := markov_wreck_hash(markov_wreck_requested_seed ~ 0x6e657874)
    if next_seed == markov_wreck_requested_seed do next_seed += 1
    return markov_wreck_lab_configure(editor, fmt.tprintf("%d", next_seed))
}

markov_wreck_return_from_flight :: proc(editor: ^Editor) -> bool {
    if editor == nil || !lab_scene_is_active(editor, "markov-wreck") || !markov_wreck_postale_spawned {
        return false
    }
    if editor.pilot.mode == .Driving {
        _ = vehicles.try_exit(&editor.pilot, true)
    }
    editor.postale_visible = false
    editor.in_map = false
    editor.pause_screen = .Closed
    editor.capture_world_only = true
    editor.camera_pose = third_person.camera_look_at({170, 82, 185}, {0, 24, 0})
    editor.editor_focus = {0, 24, 0}
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    editor.map_time = f32(rl.GetTime())
    markov_wreck_postale_spawned = false
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
    return true
}

markov_wreck_panel_color :: proc(seed: u32, fracture: bool) -> rl.Color {
    variation := u8(markov_wreck_hash(seed) % 24)
    if fracture && markov_wreck_random(seed ~ 0x7257) < .28 {
        return {u8(91 + variation), u8(72 + variation / 2), u8(57 + variation / 3), 255}
    }
    switch markov_wreck_form {
    case .Liner:
        return {u8(55 + variation / 2), u8(70 + variation / 2), u8(74 + variation / 2), 255}
    case .Dreadnought:
        return {u8(88 + variation), u8(96 + variation), u8(94 + variation / 2), 255}
    case .Carrier:
        return {u8(64 + variation), u8(75 + variation), u8(74 + variation / 2), 255}
    }
    return {92, 99, 97, 255}
}

markov_wreck_hull_list :: proc() -> f32 {
    direction := markov_wreck_hash(markov_wreck_seed ~ 0x1157) & 1 == 0 ? f32(-1) : f32(1)
    magnitude := .055 + markov_wreck_random(markov_wreck_seed ~ 0x71a7) * .055
    if markov_wreck_form == .Carrier do magnitude *= .62
    return direction * magnitude
}

markov_wreck_fracture_twist :: proc(x_index: int) -> f32 {
    return markov_wreck_parts[markov_wreck_part_for_bay(x_index)].roll
}

markov_wreck_ring_shape :: proc(x_index: int, fractured: bool) -> (radius_y, radius_z, roll: f32) {
    seed := markov_wreck_seed ~ u32(x_index * 0x9e37)
    hull_span := max(markov_wreck_last_bay - markov_wreck_first_bay, 1)
    progress := clamp(f32(x_index - markov_wreck_first_bay) / f32(hull_span), f32(0), f32(1))
    bow_progress := clamp(progress / .22, f32(0), f32(1))
    bow_progress = bow_progress * bow_progress * (3 - 2 * bow_progress)
    stern_progress := clamp((1 - progress) / .12, f32(0), f32(1))
    stern_progress = stern_progress * stern_progress * (3 - 2 * stern_progress)
    // The negative-X bow comes to a fine stem; the positive-X stern ends in a
    // broad transom suitable for a flight approach into a torn hold/hangar.
    bow_taper := .16 + .84 * bow_progress
    stern_taper := .58 + .42 * stern_progress
    taper := min(bow_taper, stern_taper)
    radius_y = (fractured ? f32(20) : f32(23)) * taper
    radius_z = (fractured ? f32(29) : f32(32)) * taper
    roll =
        markov_wreck_hull_list() +
        markov_wreck_fracture_twist(x_index) +
        (markov_wreck_random(seed) - .5) * (fractured ? f32(.12) : f32(.018))
    if markov_wreck_form == .Carrier {
        radius_y *= .82
        radius_z *= 1.22
    } else if markov_wreck_form == .Dreadnought {
        radius_y *= .94
        radius_z *= .88
    } else {
        radius_y *= 1.05
        radius_z *= 1.02
    }
    return
}

markov_wreck_local_point :: proc(x_index: int, local_y, local_z: f32) -> third_person.Vec3 {
    center := markov_wreck_ring_center(x_index)
    _, _, roll := markov_wreck_ring_shape(x_index, markov_wreck_cells[x_index] == .Fracture)
    cosine, sine := math.cos(roll), math.sin(roll)
    lateral_x := -math.sin(markov_wreck_render_yaw)
    lateral_z := math.cos(markov_wreck_render_yaw)
    rolled_z := local_y * sine + local_z * cosine
    return {
        center.x + lateral_x * rolled_z * markov_wreck_render_scale,
        center.y + (local_y * cosine - local_z * sine) * markov_wreck_render_scale,
        center.z + lateral_z * rolled_z * markov_wreck_render_scale,
    }
}

// Bind authored family details to the generated hull section beneath them.
// This preserves recognizable bridges, funnels, turrets, and islands while
// allowing their parent section to sink, shift laterally, and list.
markov_wreck_attached_point :: proc(point: third_person.Vec3) -> third_person.Vec3 {
    hull_center := f32(MARKOV_WRECK_LENGTH - 1) * .5
    x_index := int(math.round(point.x / MARKOV_WRECK_CELL + hull_center))
    x_index = clamp(x_index, markov_wreck_first_bay, markov_wreck_last_bay)
    nominal_x := (f32(x_index) - hull_center) * MARKOV_WRECK_CELL
    result := markov_wreck_local_point(x_index, point.y - MARKOV_WRECK_HULL_CENTER_Y, point.z)
    along := (point.x - nominal_x) * markov_wreck_render_scale
    result.x += math.cos(markov_wreck_render_yaw) * along
    result.z += math.sin(markov_wreck_render_yaw) * along
    return result
}

markov_wreck_attached_box :: proc(center, size: third_person.Vec3, color: rl.Color) {
    world_box_rotated(
        markov_wreck_attached_point(center),
        size * markov_wreck_render_scale,
        markov_wreck_render_yaw,
        color,
    )
}

markov_wreck_attached_box_between :: proc(a, b, up_hint: third_person.Vec3, width, height: f32, color: rl.Color) {
    world_box_between(
        markov_wreck_attached_point(a),
        markov_wreck_attached_point(b),
        up_hint,
        width * markov_wreck_render_scale,
        height * markov_wreck_render_scale,
        color,
    )
}

markov_wreck_attached_run :: proc(x_min, x_max, y, z, depth, height: f32, color: rl.Color) {
    hull_center := f32(MARKOV_WRECK_LENGTH - 1) * .5
    for x_index in markov_wreck_first_bay ..< markov_wreck_last_bay {
        if markov_wreck_cells[x_index] == .Empty ||
           markov_wreck_cells[x_index + 1] == .Empty ||
           markov_wreck_major_break_after(x_index) {
            continue
        }
        x0 := (f32(x_index) - hull_center) * MARKOV_WRECK_CELL
        x1 := (f32(x_index + 1) - hull_center) * MARKOV_WRECK_CELL
        midpoint := (x0 + x1) * .5
        if midpoint < x_min || midpoint > x_max do continue
        world_box_between(
            markov_wreck_attached_point({x0, y, z}),
            markov_wreck_attached_point({x1, y, z}),
            third_person.Vec3{0, 1, 0},
            depth * markov_wreck_render_scale,
            height * markov_wreck_render_scale,
            color,
        )
    }
}

markov_wreck_attached_run_colliders :: proc(x_min, x_max, y, z, depth, radius: f32) {
    hull_center := f32(MARKOV_WRECK_LENGTH - 1) * .5
    lanes := [3]f32{f32(-.36), 0, .36}
    for x_index in markov_wreck_first_bay ..< markov_wreck_last_bay {
        if markov_wreck_cells[x_index] == .Empty ||
           markov_wreck_cells[x_index + 1] == .Empty ||
           markov_wreck_major_break_after(x_index) {
            continue
        }
        x0 := (f32(x_index) - hull_center) * MARKOV_WRECK_CELL
        x1 := (f32(x_index + 1) - hull_center) * MARKOV_WRECK_CELL
        midpoint := (x0 + x1) * .5
        if midpoint < x_min || midpoint > x_max do continue
        for lane in lanes {
            lane_z := z + lane * depth
            markov_wreck_collider_add(
                markov_wreck_attached_point({x0, y, lane_z}),
                markov_wreck_attached_point({x1, y, lane_z}),
                radius,
            )
        }
    }
}

markov_wreck_ring_point :: proc(x_index: int, angle: f32, inset: f32 = 0) -> third_person.Vec3 {
    fractured := markov_wreck_cells[x_index] == .Fracture
    radius_y, radius_z, _ := markov_wreck_ring_shape(x_index, fractured)
    // A deep keeled maritime cross-section: broad near the weather deck,
    // narrowing through the bilges to a pronounced keel. The final four
    // points close across an open weather deck rather than making a tube.
    section := [12][2]f32 {
        {.42, 1.00},
        {-.12, .96},
        {-.55, .76},
        {-.88, .42},
        {-1.00, 0},
        {-.88, -.42},
        {-.55, -.76},
        {-.12, -.96},
        {.42, -1.00},
        {.50, -.62},
        {.50, 0},
        {.50, .62},
    }
    sample := angle / math.TAU * 12
    sample -= math.floor(sample / 12) * 12
    first := int(math.floor(sample)) % 12
    second := (first + 1) % 12
    t := sample - f32(first)
    normalized_y := section[first][0] + (section[second][0] - section[first][0]) * t
    normalized_z := section[first][1] + (section[second][1] - section[first][1]) * t
    local_y := normalized_y * max(radius_y - inset, 1)
    local_z := normalized_z * max(radius_z - inset, 1)
    return markov_wreck_local_point(x_index, local_y, local_z)
}

markov_wreck_breach :: proc(x_index, segment: int) -> bool {
    if x_index < 0 || x_index >= MARKOV_WRECK_LENGTH do return true
    cell := markov_wreck_cells[x_index]
    if cell == .Empty do return true
    seed := markov_wreck_seed ~ u32(x_index * 0x9e37) ~ u32(segment * 0x45d9)
    // Side entrances persist for several bays so they read as deliberate
    // traversal routes. Fracture gaps spread into neighboring angular plates.
    if (segment == 0 || segment == 11) && x_index % 8 < 3 do return true
    if cell != .Fracture do return markov_wreck_random(seed) < .035
    fracture_center := int(markov_wreck_hash(markov_wreck_seed ~ u32(x_index * 0x1f31)) % 12)
    angular_distance := min(abs(segment - fracture_center), 12 - abs(segment - fracture_center))
    return angular_distance <= 1 || markov_wreck_random(seed) < .18
}

markov_wreck_fragment_size :: proc(fragment_seed: u32) -> third_person.Vec3 {
    return {
        6 + markov_wreck_random(fragment_seed ~ 0x101) * 7,
        2 + markov_wreck_random(fragment_seed ~ 0x202) * 3,
        8 + markov_wreck_random(fragment_seed ~ 0x303) * 7,
    }
}

markov_wreck_fragment_center :: proc(x_index, hazard_segment, fragment: int) -> third_person.Vec3 {
    ring_center := markov_wreck_ring_center(x_index)
    ring_seed := markov_wreck_seed ~ u32(x_index * 0x9e37)
    fragment_seed := ring_seed ~ u32(fragment * 0x6d2b79f5)
    wound_angle := (f32(hazard_segment) + .5) / 12 * math.TAU
    angle_jitter := (markov_wreck_random(fragment_seed ~ 0x27d4) - .5) * .42
    outward_z := math.cos(wound_angle + angle_jitter)
    if math.abs(outward_z) < .22 {
        outward_z = markov_wreck_hash(fragment_seed ~ 0x51de) & 1 == 0 ? f32(-1) : f32(1)
    } else {
        outward_z = outward_z < 0 ? f32(-1) : f32(1)
    }
    distance := 39 + f32(fragment) * 12 + markov_wreck_random(fragment_seed ~ 0xcafe) * 8
    size := markov_wreck_fragment_size(fragment_seed)
    return {
        ring_center.x + (markov_wreck_random(fragment_seed ~ 0x3141) - .5) * 22,
        // Float with roughly half the fragment submerged.
        MARKOV_WRECK_WATERLINE + size.y * .18,
        ring_center.z + outward_z * distance,
    }
}

markov_wreck_collider_add :: proc(a, b: third_person.Vec3, radius: f32) {
    if markov_wreck_collider_count >= MARKOV_WRECK_COLLIDER_CAPACITY || radius <= 0 do return
    markov_wreck_colliders[markov_wreck_collider_count] = {
        a      = a,
        b      = b,
        radius = radius,
    }
    markov_wreck_collider_count += 1
}

markov_wreck_collider_line_x :: proc(center: third_person.Vec3, length, radius: f32) {
    markov_wreck_collider_add(
        {center.x - length * .5, center.y, center.z},
        {center.x + length * .5, center.y, center.z},
        radius,
    )
}

markov_wreck_collider_line_z :: proc(center: third_person.Vec3, length, radius: f32) {
    markov_wreck_collider_add(
        {center.x, center.y, center.z - length * .5},
        {center.x, center.y, center.z + length * .5},
        radius,
    )
}

markov_wreck_has_internal_deck :: proc(x_index: int) -> bool {
    if x_index < markov_wreck_first_bay + 3 ||
       x_index > markov_wreck_last_bay - 4 ||
       markov_wreck_cells[x_index] == .Fracture {
        return false
    }
    return (x_index - markov_wreck_first_bay) % 7 == 3
}

markov_wreck_build_colliders :: proc() {
    markov_wreck_collider_count = 0
    base_y := MARKOV_WRECK_HULL_CENTER_Y

    for x_index in 0 ..< MARKOV_WRECK_LENGTH - 1 {
        if markov_wreck_cells[x_index] == .Empty || markov_wreck_cells[x_index + 1] == .Empty do continue
        if markov_wreck_major_break_after(x_index) do continue
        for segment in 0 ..< 12 {
            if markov_wreck_breach(x_index, segment) || markov_wreck_breach(x_index + 1, segment) do continue
            angle := (f32(segment) + .5) / 12 * math.TAU
            // A capsule down each plate's centerline closely follows the
            // faceted shell while leaving authored gaps genuinely open.
            markov_wreck_collider_add(
                markov_wreck_ring_point(x_index, angle, .8),
                markov_wreck_ring_point(x_index + 1, angle, .8),
                5.2,
            )
        }
    }

    for cell, x_index in markov_wreck_cells {
        if cell == .Empty do continue
        ring_center := markov_wreck_ring_center(x_index)
        x := ring_center.x
        fractured := cell == .Fracture
        ring_seed := markov_wreck_seed ~ u32(x_index * 0x9e37)
        radius_y, radius_z, _ := markov_wreck_ring_shape(x_index, fractured)
        for segment in 0 ..< 12 {
            // A missing panel also removes its bordering frame collision.
            // Keeping either half of the frame here seals a visibly open
            // breach once the aircraft collision radius is applied.
            if markov_wreck_breach(x_index, segment) || markov_wreck_breach(x_index, (segment + 11) % 12) {
                continue
            }
            a0 := f32(segment) / 12 * math.TAU
            a1 := f32(segment + 1) / 12 * math.TAU
            markov_wreck_collider_add(
                markov_wreck_ring_point(x_index, a0, .5),
                markov_wreck_ring_point(x_index, a1, .5),
                1.6,
            )
        }
        if (!fractured && x_index % 4 == 0) || (fractured && x_index % 3 == 0) {
            markov_wreck_collider_add(
                {x, ring_center.y - radius_y - 9, ring_center.z},
                {x, ring_center.y - radius_y - 1, ring_center.z},
                4,
            )
            markov_wreck_collider_add(
                {x, ring_center.y + radius_y + 1, ring_center.z},
                {x, ring_center.y + radius_y + 13, ring_center.z},
                3.1,
            )
        }
        if markov_wreck_has_internal_deck(x_index) {
            markov_wreck_collider_add(
                markov_wreck_local_point(x_index, 3, -radius_z * .75),
                markov_wreck_local_point(x_index, 3, radius_z * .75),
                2.1,
            )
        }
        if fractured && markov_wreck_random(ring_seed ~ 0x51a7) < .22 {
            side := (ring_seed & 1) == 0 ? f32(-1) : f32(1)
            length := 18 + markov_wreck_random(ring_seed ~ 0x8128) * 18
            markov_wreck_collider_add(
                {x, ring_center.y + 10, ring_center.z + side * radius_z * .84},
                {x + 5, ring_center.y + 2, ring_center.z + side * (radius_z + length)},
                1.8,
            )
        }
        if fractured {
            hazard_segment := int(markov_wreck_hash(ring_seed ~ 0xb34c3) % 12)
            hazard_angle := (f32(hazard_segment) + .5) / 12 * math.TAU
            outer := markov_wreck_ring_point(x_index, hazard_angle, 3)
            radial := third_person.Vec3{0, outer.y - ring_center.y, outer.z - ring_center.z}
            inner := third_person.Vec3 {
                x + (markov_wreck_random(ring_seed ~ 0x991) - .5) * 7,
                ring_center.y + radial.y * .12,
                ring_center.z + radial.z * .12,
            }
            markov_wreck_collider_add(outer, inner, 2)

            if markov_wreck_hash(ring_seed ~ 0xdeb715) & 1 == 0 {
                for fragment in 0 ..< 2 {
                    fragment_seed := ring_seed ~ u32(fragment * 0x6d2b79f5)
                    fragment_center := markov_wreck_fragment_center(x_index, hazard_segment, fragment)
                    fragment_size := markov_wreck_fragment_size(fragment_seed)
                    fragment_radius := max(fragment_size.x, fragment_size.z) * .42
                    markov_wreck_collider_add(fragment_center, fragment_center, fragment_radius)
                }
            }
        }
    }

    deck_y := base_y + 12
    gunwale_sides := [2]f32{f32(-1), 1}
    for x_index in markov_wreck_first_bay ..< markov_wreck_last_bay {
        if markov_wreck_cells[x_index] == .Empty ||
           markov_wreck_cells[x_index + 1] == .Empty ||
           markov_wreck_major_break_after(x_index) {
            continue
        }
        _, radius_z0, _ := markov_wreck_ring_shape(x_index, markov_wreck_cells[x_index] == .Fracture)
        _, radius_z1, _ := markov_wreck_ring_shape(x_index + 1, markov_wreck_cells[x_index + 1] == .Fracture)
        for side in gunwale_sides {
            markov_wreck_collider_add(
                markov_wreck_local_point(x_index, 10, side * radius_z0 * .78),
                markov_wreck_local_point(x_index + 1, 10, side * radius_z1 * .78),
                2.4,
            )
        }
    }
    bow_center := markov_wreck_ring_center(markov_wreck_first_bay)
    stern_center := markov_wreck_ring_center(markov_wreck_last_bay)
    markov_wreck_collider_line_x({bow_center.x - 9, bow_center.y + 13, bow_center.z}, 28, 2.8)
    markov_wreck_collider_line_x({stern_center.x + 7, stern_center.y - 13, stern_center.z}, 22, 3.2)

    switch markov_wreck_form {
    case .Liner:
        markov_wreck_attached_run_colliders(-102, 66, deck_y + 8, 0, 18, 5.5)
        markov_wreck_attached_run_colliders(-91, 5, deck_y + 16, 0, 15, 3)
        funnel_positions := [3]f32{f32(-52), 0, 52}
        for x in funnel_positions {
            markov_wreck_collider_add(
                markov_wreck_attached_point({x, deck_y + 8, 0}),
                markov_wreck_attached_point({x, deck_y + 36, 0}),
                6,
            )
        }
        markov_wreck_collider_add(
            markov_wreck_attached_point({-104, deck_y + 8, 0}),
            markov_wreck_attached_point({-104, deck_y + 31, 0}),
            8,
        )
    case .Dreadnought:
        markov_wreck_attached_run_colliders(-78, 68, deck_y + 5, 0, 17, 4.5)
        markov_wreck_collider_add(
            markov_wreck_attached_point({-12, deck_y + 8, 0}),
            markov_wreck_attached_point({-12, deck_y + 43, 0}),
            6,
        )
        turret_positions := [3]f32{f32(-92), 58, 103}
        for x in turret_positions {
            markov_wreck_collider_add(
                markov_wreck_attached_point({x, deck_y + 6, 0}),
                markov_wreck_attached_point({x, deck_y + 10, 0}),
                9,
            )
            markov_wreck_collider_add(
                markov_wreck_attached_point({x - 30, deck_y + 10, 0}),
                markov_wreck_attached_point({x, deck_y + 10, 0}),
                2,
            )
        }
    case .Carrier:
        markov_wreck_attached_run_colliders(-131, 95, deck_y + 2, 0, 48, 3.3)
        markov_wreck_collider_add(
            markov_wreck_attached_point({55, deck_y + 3, -17}),
            markov_wreck_attached_point({55, deck_y + 29, -17}),
            9,
        )
    }
}

markov_wreck_point_segment_distance_squared :: proc(
    point, a, b: third_person.Vec3,
) -> (
    distance_squared: f32,
    closest: third_person.Vec3,
) {
    ab := third_person.Vec3{b.x - a.x, b.y - a.y, b.z - a.z}
    ap := third_person.Vec3{point.x - a.x, point.y - a.y, point.z - a.z}
    denominator := ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
    t := f32(0)
    if denominator > .000001 {
        t = clamp((ap.x * ab.x + ap.y * ab.y + ap.z * ab.z) / denominator, f32(0), f32(1))
    }
    closest = {a.x + ab.x * t, a.y + ab.y * t, a.z + ab.z * t}
    dx, dy, dz := point.x - closest.x, point.y - closest.y, point.z - closest.z
    distance_squared = dx * dx + dy * dy + dz * dz
    return
}

markov_wreck_point_blocked :: proc(point: third_person.Vec3, radius: f32) -> bool {
    for collider in markov_wreck_colliders[:markov_wreck_collider_count] {
        distance_squared, _ := markov_wreck_point_segment_distance_squared(point, collider.a, collider.b)
        combined := radius + collider.radius
        if distance_squared <= combined * combined do return true
    }
    return false
}

markov_wreck_evaluate_routes :: proc() -> Markov_Wreck_Route_Quality {
    result := Markov_Wreck_Route_Quality {
        minimum_clear_routes = 12,
    }
    required_clear_routes := markov_wreck_form == .Carrier ? 2 : 4
    for cell, x_index in markov_wreck_cells {
        if cell == .Empty do continue
        // The fine stem is intentionally structural rather than a fly-through
        // route, and the transom's terminal frames are similarly allowed to
        // close. Validation covers the immense usable hold between them.
        if x_index < markov_wreck_first_bay + 2 || x_index > markov_wreck_last_bay - 3 {
            continue
        }
        result.bays_evaluated += 1
        bay_center := markov_wreck_ring_center(x_index)
        x := bay_center.x
        if markov_wreck_point_blocked(bay_center, MARKOV_WRECK_ROUTE_CLEARANCE_RADIUS) {
            result.centerline_obstacles += 1
        }
        radius_y, radius_z, _ := markov_wreck_ring_shape(x_index, cell == .Fracture)
        route_radius_y := min(f32(13), radius_y * .35)
        route_radius_z := min(f32(11), radius_z * .35)
        clear_routes := 0
        // Probe a Postale-sized ring of alternate lines. Adjacent bays are
        // close enough that the aircraft can move between neighboring probes
        // without implausible snap turns.
        for route in 0 ..< 12 {
            angle := (f32(route) + .5) / 12 * math.TAU
            point := third_person.Vec3 {
                x,
                bay_center.y + math.sin(angle) * route_radius_y,
                bay_center.z + math.cos(angle) * route_radius_z,
            }
            if !markov_wreck_point_blocked(point, MARKOV_WRECK_ROUTE_CLEARANCE_RADIUS) do clear_routes += 1
        }
        result.minimum_clear_routes = min(result.minimum_clear_routes, clear_routes)
        if clear_routes >= required_clear_routes do result.navigable_bays += 1
    }
    result.valid =
        result.bays_evaluated >= 22 &&
        result.navigable_bays >= result.bays_evaluated - 4 &&
        result.centerline_obstacles >= 2 &&
        result.centerline_obstacles <= 12 // A wreck may contain a few completely collapsed bulkheads; the// surrounding open bays provide the alternate exterior route.
    return result
}

markov_wreck_aircraft_collision_step :: proc(editor: ^Editor) -> bool {
    if editor == nil ||
       !lab_scene_is_active(editor, "markov-wreck") ||
       editor.aircraft.active != .Postale ||
       editor.postale.crashed {
        return false
    }
    origin := third_person.Vec3 {
        editor.postale.body.position.x,
        editor.postale.body.position.y,
        editor.postale.body.position.z,
    }
    for collider in markov_wreck_colliders[:markov_wreck_collider_count] {
        origin_distance_squared, _ := markov_wreck_point_segment_distance_squared(origin, collider.a, collider.b)
        broadphase_radius := MARKOV_WRECK_POSTALE_BROADPHASE_RADIUS + collider.radius
        if origin_distance_squared > broadphase_radius * broadphase_radius do continue

        hit := false
        hit_distance_squared := collider.radius * collider.radius
        hit_point, closest := third_person.Vec3{}, third_person.Vec3{}
        for vertex in editor.postale_base_mesh.vertices[:editor.postale_base_mesh.vertex_count] {
            point := postale_vertex_world(&editor.postale, vertex.position, POSTALE_PRESENTATION_SCALE)
            distance_squared, candidate_closest := markov_wreck_point_segment_distance_squared(
                point,
                collider.a,
                collider.b,
            )
            if distance_squared > hit_distance_squared do continue
            hit = true
            hit_distance_squared = distance_squared
            hit_point = point
            closest = candidate_closest
        }
        if !hit do continue

        normal := third_person.Vec3{hit_point.x - closest.x, hit_point.y - closest.y, hit_point.z - closest.z}
        distance := f32(math.sqrt(f64(max(hit_distance_squared, .000001))))
        normal_length := distance
        if normal_length <= .001 {
            normal = {
                -editor.postale.body.basis.forward.x,
                -editor.postale.body.basis.forward.y,
                -editor.postale.body.basis.forward.z,
            }
        } else {
            normal.x /= normal_length
            normal.y /= normal_length
            normal.z /= normal_length
        }
        penetration := collider.radius - distance + .15
        origin = {
            origin.x + normal.x * penetration,
            origin.y + normal.y * penetration,
            origin.z + normal.z * penetration,
        }
        editor.postale.body.position = {origin.x, origin.y, origin.z}
        speed := linalg.length(editor.postale.body.velocity)
        editor.postale.body.velocity = {
            -editor.postale.body.velocity.x * .10 + normal.x * max(speed * .10, f32(3)),
            -editor.postale.body.velocity.y * .10 + normal.y * max(speed * .10, f32(3)),
            -editor.postale.body.velocity.z * .10 + normal.z * max(speed * .10, f32(3)),
        }
        editor.postale.structural_damage = 1
        editor.postale.flight_runtime.controls_damaged = true
        editor.postale.flight_runtime.control_authority = 0
        editor.postale.flight_runtime.engine_output = 0
        editor.postale.throttle = 0
        editor.postale.grounded = false
        editor.postale.crashed = true
        editor.postale.vehicle.position = origin
        editor.postale.vehicle.yaw_radians = postale_game.yaw_radians(editor.postale.body.basis)
        return true
    }
    return false
}

world_markov_wreck :: proc(editor: ^Editor) {
    base_y := MARKOV_WRECK_HULL_CENTER_Y

    // The lab is an open-water wreck site. A low, broad water grid provides
    // the maritime horizon and makes the ship's immense length legible.
    water := rl.Color{54, 112, 129, 238}
    WATER_EXTENT :: f32(500)
    WATER_CELL :: f32(100)
    if !markov_wreck_authored_render {
        for zi in 0 ..< 10 {
            z0 := -WATER_EXTENT + f32(zi) * WATER_CELL
            z1 := z0 + WATER_CELL
            for xi in 0 ..< 10 {
                x0 := -WATER_EXTENT + f32(xi) * WATER_CELL
                x1 := x0 + WATER_CELL
                world_water_quad(
                    {x0, MARKOV_WRECK_WATERLINE, z0},
                    {x0, MARKOV_WRECK_WATERLINE, z1},
                    {x1, MARKOV_WRECK_WATERLINE, z1},
                    {x1, MARKOV_WRECK_WATERLINE, z0},
                    water,
                )
            }
        }
    }

    // Broken, semi-transparent foam lines pin the hull to the water surface.
    // They are deliberately discontinuous so they read as wash around a
    // stranded wreck rather than a graphic outline.
    foam := rl.Color{190, 229, 220, 145}
    lee_foam := rl.Color{204, 236, 226, 182}
    foam_sides := [2]f32{f32(-1), 1}
    for side in foam_sides {
        contact_color := side * markov_wreck_hull_list() > 0 ? lee_foam : foam
        for x_index in markov_wreck_first_bay ..< markov_wreck_last_bay {
            if markov_wreck_cells[x_index] == .Empty ||
               markov_wreck_cells[x_index + 1] == .Empty ||
               markov_wreck_major_break_after(x_index) ||
               x_index % 5 == 2 {
                continue
            }
            c0 := markov_wreck_ring_center(x_index)
            c1 := markov_wreck_ring_center(x_index + 1)
            _, radius_z0, _ := markov_wreck_ring_shape(x_index, markov_wreck_cells[x_index] == .Fracture)
            _, radius_z1, _ := markov_wreck_ring_shape(x_index + 1, markov_wreck_cells[x_index + 1] == .Fracture)
            z0 := c0.z + side * radius_z0 * .84
            z1 := c1.z + side * radius_z1 * .84
            half_width := side * 1.15
            world_water_quad(
                {c0.x, MARKOV_WRECK_WATERLINE + .06, z0 - half_width},
                {c0.x, MARKOV_WRECK_WATERLINE + .06, z0 + half_width},
                {c1.x, MARKOV_WRECK_WATERLINE + .06, z1 + half_width},
                {c1.x, MARKOV_WRECK_WATERLINE + .06, z1 - half_width},
                contact_color,
            )
        }
    }

    // Thin oil and rust blooms collect in the lee of each severed section.
    // Skewed translucent quads avoid the appearance of painted rectangles.
    breaks := [2]int{markov_wreck_break_index, markov_wreck_second_break_index}
    for break_index, ordinal in breaks {
        if break_index < 0 do continue
        wound := markov_wreck_ring_center(break_index)
        salt := u32(ordinal) * 0x9e3779b9
        drift := markov_wreck_random(markov_wreck_seed ~ 0x0115 ~ salt) < .5 ? f32(-1) : f32(1)
        span_x := 24 + markov_wreck_random(markov_wreck_seed ~ 0x0116 ~ salt) * 13
        span_z := 12 + markov_wreck_random(markov_wreck_seed ~ 0x0117 ~ salt) * 8
        slick_center_z := wound.z + drift * (span_z * .55)
        world_water_quad(
            {wound.x - span_x, MARKOV_WRECK_WATERLINE + .075, slick_center_z - span_z * .35},
            {wound.x - span_x * .55, MARKOV_WRECK_WATERLINE + .075, slick_center_z + span_z},
            {wound.x + span_x, MARKOV_WRECK_WATERLINE + .075, slick_center_z + span_z * .45},
            {wound.x + span_x * .65, MARKOV_WRECK_WATERLINE + .075, slick_center_z - span_z},
            {45, 55, 48, 58},
        )
        world_water_quad(
            {wound.x - span_x * .45, MARKOV_WRECK_WATERLINE + .08, slick_center_z - span_z * .2},
            {wound.x - span_x * .3, MARKOV_WRECK_WATERLINE + .08, slick_center_z + span_z * .48},
            {wound.x + span_x * .52, MARKOV_WRECK_WATERLINE + .08, slick_center_z + span_z * .22},
            {wound.x + span_x * .35, MARKOV_WRECK_WATERLINE + .08, slick_center_z - span_z * .52},
            {126, 78, 43, 52},
        )
    }

    // Faceted hull plates span between Markov-generated rings. Each plate has
    // an exterior and a darker interior face, so flying through the shell
    // exposes real thickness and structure rather than a row of cubes.
    for x_index in 0 ..< MARKOV_WRECK_LENGTH - 1 {
        if markov_wreck_cells[x_index] == .Empty || markov_wreck_cells[x_index + 1] == .Empty do continue
        if markov_wreck_major_break_after(x_index) do continue
        fractured := markov_wreck_cells[x_index] == .Fracture || markov_wreck_cells[x_index + 1] == .Fracture
        for segment in 0 ..< 12 {
            if markov_wreck_breach(x_index, segment) || markov_wreck_breach(x_index + 1, segment) do continue
            a0 := f32(segment) / 12 * math.TAU
            a1 := f32(segment + 1) / 12 * math.TAU
            p00 := markov_wreck_ring_point(x_index, a0)
            p01 := markov_wreck_ring_point(x_index, a1)
            p11 := markov_wreck_ring_point(x_index + 1, a1)
            p10 := markov_wreck_ring_point(x_index + 1, a0)
            seed := markov_wreck_seed ~ u32(x_index * 0x9e37) ~ u32(segment)
            exterior := markov_wreck_panel_color(seed, fractured)
            interior := rl.Color{u8(f32(exterior.r) * .52), u8(f32(exterior.g) * .55), u8(f32(exterior.b) * .56), 255}
            world_quad(p00, p10, p11, p01, exterior)
            q00 := markov_wreck_ring_point(x_index, a0, 1.4)
            q01 := markov_wreck_ring_point(x_index, a1, 1.4)
            q11 := markov_wreck_ring_point(x_index + 1, a1, 1.4)
            q10 := markov_wreck_ring_point(x_index + 1, a0, 1.4)
            world_quad(q00, q01, q11, q10, interior)
        }
    }

    for cell, x_index in markov_wreck_cells {
        if cell == .Empty do continue
        ring_center := markov_wreck_ring_center(x_index)
        x := ring_center.x
        fractured := cell == .Fracture
        ring_seed := markov_wreck_seed ~ u32(x_index * 0x9e37)
        radius_y, radius_z, _ := markov_wreck_ring_shape(x_index, fractured)

        // Exposed frame arcs remain at plate boundaries. Their tangential
        // orientation gives the wreck a rib-cage silhouette at torn sections.
        for segment in 0 ..< 12 {
            if markov_wreck_breach(x_index, segment) && markov_wreck_breach(x_index, (segment + 11) % 12) {
                continue
            }
            a0 := f32(segment) / 12 * math.TAU
            a1 := f32(segment + 1) / 12 * math.TAU
            p0 := markov_wreck_ring_point(x_index, a0, .5)
            p1 := markov_wreck_ring_point(x_index, a1, .5)
            world_box_between(p0, p1, {1, 0, 0}, 2.2, 2.8, {62, 71, 71, 255})
        }

        // Surviving keel knees and sparse deck stanchions reveal construction
        // without turning every procedural bay into the same comb tooth.
        if (!fractured && x_index % 4 == 0) || (fractured && x_index % 3 == 0) {
            steel := markov_wreck_panel_color(ring_seed ~ 0xa11ce, fractured)
            world_box_rotated(
                markov_wreck_local_point(x_index, -radius_y - 5, 0),
                third_person.Vec3{7.2, 8, 8} * markov_wreck_render_scale,
                markov_wreck_render_yaw,
                steel,
            )
            world_box_rotated(
                markov_wreck_local_point(x_index, radius_y + 7, 0),
                third_person.Vec3{6.2, 12, 6.2} * markov_wreck_render_scale,
                markov_wreck_render_yaw,
                steel,
            )
        }

        // Surviving internal deck plates make the open shell read as a ship's
        // hold. Their matching colliders turn them into over/under choices.
        if markov_wreck_has_internal_deck(x_index) {
            port := markov_wreck_local_point(x_index, 3, -radius_z * .75)
            starboard := markov_wreck_local_point(x_index, 3, radius_z * .75)
            half_bay := MARKOV_WRECK_CELL * .44 * markov_wreck_render_scale
            along_x, along_z :=
                math.cos(markov_wreck_render_yaw) * half_bay, math.sin(markov_wreck_render_yaw) * half_bay
            world_quad(
                {port.x - along_x, port.y, port.z - along_z},
                {starboard.x - along_x, starboard.y, starboard.z - along_z},
                {starboard.x + along_x, starboard.y, starboard.z + along_z},
                {port.x + along_x, port.y, port.z + along_z},
                {83, 88, 82, 255},
            )
            brace_start := markov_wreck_local_point(x_index, 4.5, radius_z * .08)
            brace_end := markov_wreck_local_point(x_index, 4.5, radius_z * .38)
            world_box_between(brace_start, brace_end, {1, 0, 0}, 3, 2, {151, 94, 52, 255})
        }

        // A few snapped cargo booms or lifeboat davits project from fracture
        // bays. Their drooping diagonal distinguishes them from sci-fi spars.
        if fractured && markov_wreck_random(ring_seed ~ 0x51a7) < .22 {
            side := (ring_seed & 1) == 0 ? f32(-1) : f32(1)
            length := 18 + markov_wreck_random(ring_seed ~ 0x8128) * 18
            world_box_between(
                {x, ring_center.y + 10, ring_center.z + side * radius_z * .84},
                {x + 5, ring_center.y + 2, ring_center.z + side * (radius_z + length)},
                {1, 0, 0},
                3,
                3,
                {73, 81, 80, 255},
            )
        }

        if fractured {
            // A snapped internal frame reaches only partway across the hold,
            // forcing a readable left/right or over/under choice without
            // sealing the route. Its angular position is stable per seed.
            hazard_segment := int(markov_wreck_hash(ring_seed ~ 0xb34c3) % 12)
            hazard_angle := (f32(hazard_segment) + .5) / 12 * math.TAU
            outer := markov_wreck_ring_point(x_index, hazard_angle, 3)
            radial := third_person.Vec3{0, outer.y - ring_center.y, outer.z - ring_center.z}
            inner := third_person.Vec3 {
                x + (markov_wreck_random(ring_seed ~ 0x991) - .5) * 7,
                ring_center.y + radial.y * .12,
                ring_center.z + radial.z * .12,
            }
            world_box_between(outer, inner, {1, 0, 0}, 3.4, 3.4, {57, 66, 66, 255})
            // Ochre end caps identify the obstacle's reachable tip from the
            // approach, making the safer side readable before the last moment.
            world_box(inner, {4.8, 4.8, 4.8}, {218, 153, 64, 255})
            world_box({inner.x - 1.5, inner.y + 1.5, inner.z}, {1.2, 1.2, 1.2}, {249, 216, 128, 255})

            // Selected wounds cast a short, directional debris trail. Keeping
            // this sparse preserves the wreck as the dominant landmark while
            // widening a few fracture bays into exterior flight obstacles.
            if markov_wreck_hash(ring_seed ~ 0xdeb715) & 1 != 0 do continue
            for fragment in 0 ..< 2 {
                fragment_seed := ring_seed ~ u32(fragment * 0x6d2b79f5)
                fragment_center := markov_wreck_fragment_center(x_index, hazard_segment, fragment)
                fragment_size := markov_wreck_fragment_size(fragment_seed)
                world_box_rotated(
                    fragment_center,
                    fragment_size,
                    markov_wreck_random(fragment_seed ~ 0x404) * math.TAU,
                    markov_wreck_panel_color(fragment_seed, true),
                )
            }
        }
    }

    // Broken gunwales and keel members run longitudinally through the damage.
    bone := rl.Color{53, 63, 65, 255}
    deck_y := base_y + 12
    gunwale_sides := [2]f32{f32(-1), 1}
    for x_index in markov_wreck_first_bay ..< markov_wreck_last_bay {
        if markov_wreck_cells[x_index] == .Empty ||
           markov_wreck_cells[x_index + 1] == .Empty ||
           markov_wreck_major_break_after(x_index) {
            continue
        }
        _, radius_z0, _ := markov_wreck_ring_shape(x_index, markov_wreck_cells[x_index] == .Fracture)
        _, radius_z1, _ := markov_wreck_ring_shape(x_index + 1, markov_wreck_cells[x_index + 1] == .Fracture)
        for side in gunwale_sides {
            world_box_between(
                markov_wreck_local_point(x_index, 10, side * radius_z0 * .78),
                markov_wreck_local_point(x_index + 1, 10, side * radius_z1 * .78),
                {1, 0, 0},
                3.6,
                3.6,
                bone,
            )
        }
    }
    bow_center := markov_wreck_ring_center(markov_wreck_first_bay)
    stern_center := markov_wreck_ring_center(markov_wreck_last_bay)
    along_x, along_z := math.cos(markov_wreck_render_yaw), math.sin(markov_wreck_render_yaw)
    world_box_rotated(
        {
            bow_center.x - along_x * 9 * markov_wreck_render_scale,
            bow_center.y + 13 * markov_wreck_render_scale,
            bow_center.z - along_z * 9 * markov_wreck_render_scale,
        },
        third_person.Vec3{28, 4, 4} * markov_wreck_render_scale,
        markov_wreck_render_yaw,
        {69, 75, 72, 255},
    )
    world_box_rotated(
        {
            stern_center.x + along_x * 7 * markov_wreck_render_scale,
            stern_center.y - 13 * markov_wreck_render_scale,
            stern_center.z + along_z * 7 * markov_wreck_render_scale,
        },
        third_person.Vec3{22, 4.8, 4.8} * markov_wreck_render_scale,
        markov_wreck_render_yaw,
        {81, 72, 60, 255},
    )

    // Each seed belongs to a broad landmark family with a distinct skyline.
    switch markov_wreck_form {
    case .Liner:
        ivory := rl.Color{190, 190, 169, 255}
        markov_wreck_attached_run(-102, 66, deck_y + 8, 0, 18, 14, ivory)
        markov_wreck_attached_run(-91, 5, deck_y + 16, 0, 15, 5, {159, 164, 153, 255})
        // A stepped bridge and three immense funnels establish an ocean-liner
        // silhouette even when most of the hull is torn open.
        markov_wreck_attached_box({-104, deck_y + 10, 0}, {24, 19, 24}, ivory)
        markov_wreck_attached_box({-111, deck_y + 21, 0}, {13, 6, 27}, {153, 165, 160, 255})
        funnel_positions := [3]f32{f32(-52), 0, 52}
        for x in funnel_positions {
            world_tapered_box_rotated(
                markov_wreck_attached_point({x, deck_y + 22, 0}),
                28,
                11,
                13,
                8,
                10,
                markov_wreck_render_yaw,
                {154, 83, 54, 255},
            )
            markov_wreck_attached_box({x, deck_y + 34, 0}, {8.5, 4, 10.5}, {43, 48, 47, 255})
        }
        markov_wreck_attached_box({-128, deck_y + 31, 0}, {3.2, 38, 3.2}, {59, 66, 65, 255})
        markov_wreck_attached_box_between(
            {-128, deck_y + 43, 0},
            {-99, deck_y + 25, 19},
            {1, 0, 0},
            2,
            2,
            {66, 72, 70, 255},
        )
        // Rows of portholes and surviving lifeboats establish human scale.
        detail_positions := [7]f32{f32(-91), -66, -31, 6, 39, 72, 101}
        for x in detail_positions {
            markov_wreck_attached_box({x, deck_y + 10, -9.2}, {5, 2.2, 1}, {31, 50, 53, 255})
            markov_wreck_attached_box({x, deck_y + 10, 9.2}, {5, 2.2, 1}, {31, 50, 53, 255})
        }
        boat_positions := [4]f32{f32(-73), -27, 24, 76}
        for x in boat_positions {
            markov_wreck_attached_box({x, deck_y + 15, -11}, {15, 3.4, 3.2}, {202, 160, 86, 255})
            markov_wreck_attached_box({x, deck_y + 15, 11}, {15, 3.4, 3.2}, {202, 160, 86, 255})
        }
    case .Dreadnought:
        naval := rl.Color{105, 112, 109, 255}
        markov_wreck_attached_run(-78, 68, deck_y + 5, 0, 17, 10, naval)
        markov_wreck_attached_box({-12, deck_y + 15, 0}, {34, 20, 22}, {92, 101, 99, 255})
        markov_wreck_attached_box({-12, deck_y + 34, 0}, {5, 38, 5}, {55, 62, 62, 255})
        turret_positions := [3]f32{f32(-92), 58, 103}
        for x in turret_positions {
            world_vertical_prism(
                markov_wreck_attached_point({x, deck_y + 7, 0}),
                10,
                11,
                8,
                markov_wreck_render_yaw,
                {82, 91, 91, 255},
            )
            markov_wreck_attached_box({x - 15, deck_y + 11, -3}, {31, 3.2, 3.2}, {54, 61, 61, 255})
            markov_wreck_attached_box({x - 15, deck_y + 11, 3}, {31, 3.2, 3.2}, {54, 61, 61, 255})
        }
        markov_wreck_attached_box_between(
            {-12, deck_y + 41, 0},
            {20, deck_y + 17, -23},
            {1, 0, 0},
            2.2,
            2.2,
            {58, 65, 64, 255},
        )
        secondary_positions := [4]f32{f32(-61), -34, 27, 82}
        for x in secondary_positions {
            world_vertical_prism(
                markov_wreck_attached_point({x, deck_y + 8, -13}),
                5,
                5,
                5,
                markov_wreck_render_yaw,
                {74, 82, 81, 255},
            )
            world_vertical_prism(
                markov_wreck_attached_point({x, deck_y + 8, 13}),
                5,
                5,
                5,
                markov_wreck_render_yaw,
                {74, 82, 81, 255},
            )
        }
    case .Carrier:
        markov_wreck_attached_run(-131, 95, deck_y + 2, 0, 48, 5.5, {75, 83, 82, 255})
        // The torn flight deck retains jagged end slabs and an island.
        markov_wreck_attached_box({-119, deck_y + 5, 0}, {18, 3, 58}, {55, 63, 63, 255})
        markov_wreck_attached_box({103, deck_y + 5, 0}, {27, 3, 58}, {55, 63, 63, 255})
        markov_wreck_attached_box({55, deck_y + 14, -17}, {20, 24, 17}, {104, 110, 104, 255})
        markov_wreck_attached_box({55, deck_y + 31, -17}, {4, 18, 4}, {51, 59, 59, 255})
        markov_wreck_attached_box_between(
            {55, deck_y + 38, -17},
            {79, deck_y + 23, 4},
            {1, 0, 0},
            2,
            2,
            {54, 62, 61, 255},
        )
        // Faded centerline and elevators distinguish the deck from a barge.
        markov_wreck_attached_box({-42, deck_y + 5.1, 0}, {116, .35, 1.4}, {201, 190, 141, 255})
        markov_wreck_attached_box({30, deck_y + 5.15, 13}, {24, .4, 17}, {48, 56, 56, 255})
        markov_wreck_attached_box({-72, deck_y + 5.15, -13}, {21, .4, 17}, {48, 56, 56, 255})
    }

    // This lab replaces the ordinary world, so the shared world pass returns
    // before it submits gameplay vehicles. Keep the spawned flight-mode craft
    // and its seated pilot in the lab's self-contained render pass.
    if !markov_wreck_authored_render {
        world_aircraft(editor)
        world_postale_pilot(editor)
    }
}

world_authored_wrecks :: proc(editor: ^Editor) {
    if editor == nil do return
    markov_wreck_authored_render = true
    for &wreck in editor.wrecks[:editor.wreck_count] {
        markov_wreck_instance_load(&wreck)
        world_markov_wreck(editor)
    }
    if editor.wreck_paint_mode && editor.wreck_preview_valid {
        markov_wreck_instance_load(&editor.wreck_preview)
        world_markov_wreck(editor)
    }
    markov_wreck_authored_render = false
    markov_wreck_render_origin_x = 0
    markov_wreck_render_origin_z = 0
    markov_wreck_render_yaw = 0
    markov_wreck_render_scale = 1
}

markov_wreck_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    if markov_wreck_postale_spawned {
        _ = markov_wreck_ensure_flight_control(editor)
        return
    }
    if rl.IsMouseButtonPressed(.LEFT) {
        mouse := rl.GetMousePosition()
        if rl.CheckCollisionPointRec(mouse, markov_wreck_spawn_button_bounds(rl.GetScreenHeight())) {
            _ = markov_wreck_spawn_postale(editor)
        } else if rl.CheckCollisionPointRec(mouse, markov_wreck_randomize_button_bounds(rl.GetScreenHeight())) {
            _ = markov_wreck_randomize(editor)
        }
    }
}

markov_wreck_draw_ui :: proc(_: ^Editor, _: i32, height: i32) {
    if markov_wreck_postale_spawned do return
    mouse := rl.GetMousePosition()
    spawn := markov_wreck_spawn_button_bounds(height)
    randomize := markov_wreck_randomize_button_bounds(height)
    spawn_fill := rl.CheckCollisionPointRec(mouse, spawn) ? rl.Color{52, 125, 131, 248} : rl.Color{34, 79, 85, 244}
    randomize_fill :=
        rl.CheckCollisionPointRec(mouse, randomize) ? rl.Color{111, 91, 52, 248} : rl.Color{72, 61, 40, 244}
    rl.DrawRectangleRounded(spawn, .18, 8, spawn_fill)
    rl.DrawRectangleRoundedLinesEx(spawn, .18, 8, 1.5, {151, 225, 216, 255})
    rl.DrawTextEx(rl.Font{}, "SPAWN POSTALE", {spawn.x + 22, spawn.y + 13}, 19, 1, {242, 252, 245, 255})
    rl.DrawRectangleRounded(randomize, .18, 8, randomize_fill)
    rl.DrawRectangleRoundedLinesEx(randomize, .18, 8, 1.5, {224, 195, 132, 255})
    rl.DrawTextEx(rl.Font{}, "RANDOMIZE WRECK", {randomize.x + 17, randomize.y + 13}, 18, .8, {255, 243, 211, 255})
}
