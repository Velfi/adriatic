package main

import air_effects "../packages/air_effects"
import atmosphere "../packages/atmosphere"
import chase_camera "../packages/chase_camera"
import flight "../packages/flight"
import postale_game "../packages/postale"
import rondine_game "../packages/rondine"
import surface_weather "../packages/surface_weather"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import wind_audio "../packages/wind_audio"
import "core:math"
import "core:math/linalg"

active_aircraft_wing_trail_anchors :: proc(
    editor: ^Editor,
) -> (
    left_tip, right_tip: third_person.Vec3,
    basis: flight.Basis,
    available: bool,
) {
    if editor == nil do return
    if editor.aircraft.active == .Rondine {
        left_tip = world_rondine_local(
            editor,
            {-RONDINE_WING_TRAIL_LOCAL_X, RONDINE_WING_TRAIL_LOCAL_Y, RONDINE_WING_TRAIL_LOCAL_Z},
        )
        right_tip = world_rondine_local(
            editor,
            {RONDINE_WING_TRAIL_LOCAL_X, RONDINE_WING_TRAIL_LOCAL_Y, RONDINE_WING_TRAIL_LOCAL_Z},
        )
        basis = world_rondine_presentation_basis(editor)
        available = true
        return
    }
    if editor.aircraft.active != .Postale do return
    left_tip = postale_vertex_world(
        &editor.postale,
        {-POSTALE_WING_TRAIL_LOCAL_X, POSTALE_WING_TRAIL_LOCAL_Y, POSTALE_WING_TRAIL_LOCAL_Z},
        POSTALE_PRESENTATION_SCALE,
    )
    right_tip = postale_vertex_world(
        &editor.postale,
        {POSTALE_WING_TRAIL_LOCAL_X, POSTALE_WING_TRAIL_LOCAL_Y, POSTALE_WING_TRAIL_LOCAL_Z},
        POSTALE_PRESENTATION_SCALE,
    )
    basis = flight.basis_from_orientation(editor.postale.body.orientation)
    available = true
    return
}

@(no_instrumentation)
postale_normal_world :: #force_inline proc(runtime: ^postale_game.Runtime, normal: [3]f32) -> third_person.Vec3 {
    basis := flight.basis_from_orientation(runtime.body.orientation)
    return {
        -basis.right.x * normal[0] + basis.up.x * normal[1] + basis.forward.x * normal[2],
        -basis.right.y * normal[0] + basis.up.y * normal[1] + basis.forward.y * normal[2],
        -basis.right.z * normal[0] + basis.up.z * normal[1] + basis.forward.z * normal[2],
    }
}

aircraft_camera_target :: proc(editor: ^Editor) -> chase_camera.Target {
    body := aircraft_render_body(editor)
    basis := flight.basis_from_orientation(body.orientation)
    if editor.aircraft.active == .Rondine {
        return {
            position = body.position,
            basis = basis,
            airspeed = active_aircraft_apparent_airflow_speed(editor),
            roll_input = editor.flight_control.roll,
            grounded = editor.rondine.grounded,
            follow_distance = 15.5,
            follow_height = 4.2,
            follow_side = 2.1,
            focus_height = .8,
        }
    } else if editor.aircraft.active != .Postale {
        return {
            position = body.position,
            basis = basis,
            airspeed = active_aircraft_apparent_airflow_speed(editor),
            roll_input = editor.flight_control.roll,
            grounded = editor.libellula.grounded,
            fixed_framing = true,
        }
    }
    return {
        position        = body.position,
        basis           = basis,
        airspeed        = active_aircraft_apparent_airflow_speed(editor),
        roll_input      = editor.flight_control.roll,
        grounded        = editor.postale.grounded,
        // The Postale's broad parasol wing needs a low, long-lens-like rear
        // view. The generic close/high framing flattened it into a top-down
        // silhouette and made the aircraft read as a toy.
        follow_distance = editor.capture_postale_bank_grid ? f32(82) : f32(12.5),
        follow_height   = editor.capture_postale_bank_grid ? f32(42) : f32(3.35),
        focus_height    = editor.capture_postale_bank_grid ? f32(0) : f32(.65),
    }
}

BOMBER_DROP_CAPACITY :: 24
BOMBER_CHUTE_DELAY :: f32(.55)
BOMBER_DROP_COOLDOWN :: f32(.28)
BOMBER_SIMULATION_STEP :: f32(.04)

Bomber_Pip_Layout :: struct {
    x, y:          f32,
    width, height: f32,
}

bomber_pip_layout :: proc(width, height: f32) -> Bomber_Pip_Layout {
    margin := clamp(width * .07, f32(12), f32(92))
    top := clamp(height * .122, f32(12), f32(88))
    pip_width := min(clamp(width * .29, f32(180), f32(430)), max(width - margin - 12, f32(1)))
    pip_height := pip_width * 9 / 16
    if top + pip_height > height - 12 {
        pip_height = max(height - top - 12, f32(1))
        pip_width = pip_height * 16 / 9
    }
    return {x = max(width - pip_width - margin, f32(0)), y = top, width = pip_width, height = pip_height}
}

Bomber_Payload_Kind :: enum {
    Mail,
    Parcel,
    Supplies,
}

Bomber_Drop :: struct {
    position:       third_person.Vec3,
    velocity:       third_person.Vec3,
    kind:           Bomber_Payload_Kind,
    age:            f32,
    landed_seconds: f32,
    parachute_open: bool,
    landed:         bool,
    seed:           u32,
}

bomber_payload_label :: proc(kind: Bomber_Payload_Kind) -> cstring {
    switch kind {
    case .Mail:
        return "MAIL"
    case .Parcel:
        return "PARCEL"
    case .Supplies:
        return "SUPPLIES"
    }
    return "PAYLOAD"
}

bomber_payload_cycle :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.bomber_payload_kind = cast(Bomber_Payload_Kind)((int(editor.bomber_payload_kind) + 1) %
        len(Bomber_Payload_Kind))
}

bomber_drop_initial_state :: proc(body: flight.Body_State, kind: Bomber_Payload_Kind, seed: u32) -> Bomber_Drop {
    basis := flight.basis_from_orientation(body.orientation)
    return {
        position = {
            body.position.x - basis.up.x * .55,
            body.position.y - basis.up.y * .55,
            body.position.z - basis.up.z * .55,
        },
        velocity = {body.velocity.x, body.velocity.y - .7, body.velocity.z},
        kind = kind,
        seed = seed,
    }
}

bomber_drop_integrate :: proc(
    editor: ^Editor,
    drop: ^Bomber_Drop,
    delta_seconds: f32,
    compensate_wind := true,
) -> bool {
    drop.age += delta_seconds
    if drop.age >= BOMBER_CHUTE_DELAY do drop.parachute_open = true
    wind := third_person.Vec3{}
    if compensate_wind {
        local := atmosphere_local_weather(editor, drop.position)
        wind = {local.wind[0], local.wind[1], local.wind[2]}
    }
    if drop.parachute_open {
        horizontal_response := min(delta_seconds * 1.35, f32(1))
        drop.velocity.x += (wind.x - drop.velocity.x) * horizontal_response
        drop.velocity.z += (wind.z - drop.velocity.z) * horizontal_response
        drop.velocity.y += (-5.4 - drop.velocity.y) * min(delta_seconds * 2.8, f32(1))
    } else {
        drop.velocity.y -= 9.81 * delta_seconds
    }
    drop.position += drop.velocity * delta_seconds
    surface := max(
        terrain.sample_surface_height(&editor.project, 0, drop.position.x, drop.position.z),
        editor.project.sea_level,
    )
    surface = terrain.structure_collision_surface_height(&editor.project, drop.position.x, drop.position.z, surface)
    if drop.position.y > surface + .18 do return false
    drop.position.y = surface + .18
    drop.velocity = {}
    drop.landed = true
    return true
}

bomber_drop_release :: proc(editor: ^Editor) {
    if editor == nil || editor.bomber_drop_cooldown > 0 do return
    body := active_aircraft_body(editor)
    if body == nil do return
    drop := bomber_drop_initial_state(body^, editor.bomber_payload_kind, editor.bomber_drop_serial)
    editor.bomber_drop_serial += 1
    if editor.bomber_drop_count < BOMBER_DROP_CAPACITY {
        editor.bomber_drops[editor.bomber_drop_count] = drop
        editor.bomber_drop_count += 1
    } else {
        // Replace the oldest payload so repeated drops remain bounded.
        oldest := 0
        oldest_age := editor.bomber_drops[0].age + editor.bomber_drops[0].landed_seconds
        for index in 1 ..< BOMBER_DROP_CAPACITY {
            age := editor.bomber_drops[index].age + editor.bomber_drops[index].landed_seconds
            if age > oldest_age {
                oldest, oldest_age = index, age
            }
        }
        editor.bomber_drops[oldest] = drop
    }
    editor.bomber_drop_cooldown = BOMBER_DROP_COOLDOWN
    editor.bomber_release_flash = 1
}

bomber_drop_step :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    editor.bomber_drop_cooldown = max(editor.bomber_drop_cooldown - delta_seconds, f32(0))
    editor.bomber_release_flash = max(editor.bomber_release_flash - delta_seconds * 4.5, f32(0))
    editor.bomber_touchdown_flash = max(editor.bomber_touchdown_flash - delta_seconds * 1.4, f32(0))
    index := 0
    for index < editor.bomber_drop_count {
        drop := &editor.bomber_drops[index]
        if drop.landed {
            drop.landed_seconds += delta_seconds
            if drop.landed_seconds > 20 {
                editor.bomber_drop_count -= 1
                editor.bomber_drops[index] = editor.bomber_drops[editor.bomber_drop_count]
                continue
            }
            index += 1
            continue
        }
        remaining := delta_seconds
        landed := false
        for remaining > 0 {
            step := min(remaining, BOMBER_SIMULATION_STEP)
            if bomber_drop_integrate(editor, drop, step) {
                landed = true
                break
            }
            remaining -= step
        }
        if landed {
            editor.bomber_touchdown_flash = 1
            editor.bomber_touchdown_kind = drop.kind
        }
        index += 1
    }
}

bomber_pip_drop_from :: proc(drops: []Bomber_Drop) -> ^Bomber_Drop {
    newest_index := -1
    newest_seed := u32(0)
    for &drop, index in drops {
        if drop.landed do continue
        if newest_index < 0 || drop.seed > newest_seed {
            newest_index = index
            newest_seed = drop.seed
        }
    }
    if newest_index < 0 do return nil
    return &drops[newest_index]
}

bomber_pip_drop :: proc(editor: ^Editor) -> ^Bomber_Drop {
    if editor == nil do return nil
    return bomber_pip_drop_from(editor.bomber_drops[:editor.bomber_drop_count])
}

bomber_pip_camera_pose :: proc(editor: ^Editor, drop: ^Bomber_Drop) -> third_person.Camera_Pose {
    if editor == nil || drop == nil do return {}
    horizontal_velocity := third_person.Vec3{drop.velocity.x, 0, drop.velocity.z}
    travel := linalg.normalize0(horizontal_velocity)
    if linalg.length(horizontal_velocity) < .2 {
        basis := flight.basis_from_orientation(active_aircraft_body(editor).orientation)
        travel = {basis.forward.x, 0, basis.forward.z}
    }
    side := third_person.Vec3{-travel.z, 0, travel.x}
    camera_position := third_person.Vec3 {
        drop.position.x - travel.x * 6.8 + side.x * 2.5,
        drop.position.y + 3.4,
        drop.position.z - travel.z * 6.8 + side.z * 2.5,
    }
    surface := max(
        terrain.sample_surface_height(&editor.project, 0, camera_position.x, camera_position.z),
        editor.project.sea_level,
    )
    camera_position.y = max(camera_position.y, surface + 1.4)
    target := drop.position
    target.y += drop.parachute_open ? f32(.75) : f32(.15)
    return third_person.camera_look_at(camera_position, target)
}

bomber_pip_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    tracked := bomber_pip_drop(editor)
    if tracked == nil {
        editor.bomber_pip_valid = false
        editor.bomber_pip_handoff_seconds = 0
        return
    }
    desired := bomber_pip_camera_pose(editor, tracked)
    if !editor.bomber_pip_valid {
        editor.bomber_pip_pose = desired
        editor.bomber_pip_seed = tracked.seed
        editor.bomber_pip_valid = true
        return
    }
    if editor.bomber_pip_seed != tracked.seed {
        editor.bomber_pip_seed = tracked.seed
        editor.bomber_pip_handoff_seconds = .45
    }
    sharpness := editor.bomber_pip_handoff_seconds > 0 ? f32(4.5) : f32(10)
    editor.bomber_pip_pose = third_person.follow_camera(editor.bomber_pip_pose, desired, sharpness, delta_seconds)
    editor.bomber_pip_handoff_seconds = max(editor.bomber_pip_handoff_seconds - delta_seconds, f32(0))
}

bomber_drop_eta :: proc(editor: ^Editor, source: ^Bomber_Drop) -> f32 {
    if editor == nil || source == nil || source.landed do return 0
    drop := source^
    elapsed := f32(0)
    for _ in 0 ..< 1500 {
        elapsed += BOMBER_SIMULATION_STEP
        if bomber_drop_integrate(editor, &drop, BOMBER_SIMULATION_STEP) do return elapsed
    }
    return elapsed
}

bomber_predicted_impact_for_wind :: proc(editor: ^Editor, compensate_wind: bool) -> third_person.Vec3 {
    body := active_aircraft_body(editor)
    if body == nil do return {}
    drop := bomber_drop_initial_state(body^, editor.bomber_payload_kind, 0)
    for _ in 0 ..< 1500 {
        if bomber_drop_integrate(editor, &drop, BOMBER_SIMULATION_STEP, compensate_wind) {
            return drop.position
        }
    }
    return drop.position
}

bomber_predicted_impact :: proc(editor: ^Editor) -> third_person.Vec3 {
    return bomber_predicted_impact_for_wind(editor, true)
}

bomber_camera_pose :: proc(editor: ^Editor) -> third_person.Camera_Pose {
    body := aircraft_render_body(editor)
    basis := flight.basis_from_orientation(body.orientation)
    impact := bomber_predicted_impact(editor)
    eye := third_person.Vec3 {
        body.position.x + basis.forward.x * 1.8 - basis.up.x * 2.15,
        body.position.y + basis.forward.y * 1.8 - basis.up.y * 2.15,
        body.position.z + basis.forward.z * 1.8 - basis.up.z * 2.15,
    }
    return third_person.camera_look_at(eye, impact)
}

aircraft_render_body :: proc(editor: ^Editor) -> flight.Body_State {
    body := active_aircraft_body(editor)^
    if !editor.aircraft_previous_body_valid do return body
    alpha := f32(editor.aircraft_fixed_accumulator / AIRCRAFT_FIXED_STEP)
    previous := editor.aircraft_previous_body
    result := body
    result.position = linalg.lerp(previous.position, body.position, alpha)
    result.velocity = linalg.lerp(previous.velocity, body.velocity, alpha)
    result.angular_velocity_world = linalg.lerp(previous.angular_velocity_world, body.angular_velocity_world, alpha)
    result.orientation = flight.interpolate_orientation(previous.orientation, body.orientation, alpha)
    return result
}

@(no_instrumentation)
active_aircraft_body :: #force_inline proc(editor: ^Editor) -> ^flight.Body_State {
    if editor != nil && editor.aircraft.active == .Rondine do return &editor.rondine.body
    if editor != nil && editor.aircraft.active != .Postale do return &editor.libellula.body
    if editor == nil do return nil
    return &editor.postale.body
}

active_aircraft_vehicle :: proc(editor: ^Editor) -> ^vehicles.Vehicle {
    if editor == nil do return nil
    slot := vehicles.aircraft_fleet_active(&editor.aircraft)
    if slot == nil do return nil
    return slot.vehicle
}

active_aircraft_throttle :: proc(editor: ^Editor) -> f32 {
    if editor != nil && editor.aircraft.active == .Rondine do return editor.rondine.throttle
    if editor != nil && editor.aircraft.active != .Postale do return editor.libellula.throttle
    if editor == nil do return 0
    return editor.postale.throttle
}

active_aircraft_airspeed :: proc(editor: ^Editor) -> f32 {
    if editor != nil && editor.aircraft.active == .Rondine do return editor.rondine.telemetry.speed
    if editor != nil && editor.aircraft.active != .Postale do return linalg.length(editor.libellula.body.velocity)
    if editor == nil do return 0
    return postale_game.selected_airspeed(&editor.postale)
}

active_aircraft_apparent_airflow_speed :: proc(editor: ^Editor) -> f32 {
    if editor == nil do return 0
    body := active_aircraft_body(editor)
    wind := aircraft_local_airflow(editor, body)
    return wind_audio.apparent_airflow_speed(wind.x, wind.z, body.velocity.x, body.velocity.z, body.velocity.y)
}

active_aircraft_grounded :: proc(editor: ^Editor) -> bool {
    if editor == nil do return true
    if editor.aircraft.active == .Rondine do return editor.rondine.grounded
    if editor.aircraft.active != .Postale do return editor.libellula.grounded
    return editor.postale.grounded
}

active_aircraft_crashed :: proc(editor: ^Editor) -> bool {
    if editor == nil do return true
    if editor.aircraft.active == .Rondine do return editor.rondine.crashed
    if editor.aircraft.active != .Postale do return editor.libellula.crashed
    return editor.postale.crashed
}

atmosphere_local_weather :: proc(editor: ^Editor, position: third_person.Vec3) -> atmosphere.Local_Weather {
    if editor == nil do return {}
    terrain_ctx := atmosphere_terrain_context(editor, position)
    return atmosphere.sample_at(
        &editor.atmosphere,
        {position.x, position.y, position.z},
        terrain_ctx.altitude_agl,
        terrain_ctx,
    )
}

atmosphere_terrain_context :: proc(editor: ^Editor, position: third_person.Vec3) -> atmosphere.Terrain_Context {
    if editor == nil do return {}
    sample_distance := f32(45)
    ground := terrain.sample_surface_height(&editor.project, 0, position.x, position.z)
    east := terrain.sample_surface_height(&editor.project, 0, position.x + sample_distance, position.z)
    west := terrain.sample_surface_height(&editor.project, 0, position.x - sample_distance, position.z)
    north := terrain.sample_surface_height(&editor.project, 0, position.x, position.z + sample_distance)
    south := terrain.sample_surface_height(&editor.project, 0, position.x, position.z - sample_distance)
    gradient := [2]f32{(east - west) / (sample_distance * 2), (north - south) / (sample_distance * 2)}
    land := ground > editor.project.sea_level + .1
    directions := [8][2]f32 {
        {1, 0},
        {-1, 0},
        {0, 1},
        {0, -1},
        {.7071068, .7071068},
        {-.7071068, .7071068},
        {.7071068, -.7071068},
        {-.7071068, -.7071068},
    }
    coast_distance := f32(1800)
    coast_to_sea := [2]f32{}
    for distance := f32(160); distance <= 1440; distance += 160 {
        found := false
        for direction in directions {
            height := terrain.sample_surface_height(
                &editor.project,
                0,
                position.x + direction[0] * distance,
                position.z + direction[1] * distance,
            )
            sample_land := height > editor.project.sea_level + .1
            if sample_land == land do continue
            coast_distance = distance
            coast_to_sea = land ? direction : -direction
            found = true
            break
        }
        if found do break
    }
    gradient_strength := f32(math.sqrt(f64(gradient[0] * gradient[0] + gradient[1] * gradient[1])))
    return {
        valid = true,
        altitude_agl = max(position.y - ground, f32(0)),
        terrain_height = ground,
        terrain_gradient = gradient,
        sea_level = editor.project.sea_level,
        land = land,
        coast_to_sea = coast_to_sea,
        coast_distance = coast_distance,
        terrain_channel = clamp(gradient_strength * 2.2, 0, 1),
    }
}

atmosphere_sky :: proc(editor: ^Editor) -> atmosphere.Sky_State {
    if editor == nil do return {}
    position := editor.camera_pose.position
    terrain_ctx := atmosphere_terrain_context(editor, position)
    sky := atmosphere.sample(&editor.atmosphere, {position.x, position.y, position.z}, terrain_ctx)
    if lab_scene_is_active(editor, "rainbow") {
        // This lab deliberately authors an intermediate sun-shower rather
        // than one of atmosphere's uniform public presets.
        sky.weather = editor.atmosphere.weather
    }
    return sky
}

surface_weather_sample :: proc(editor: ^Editor, position: third_person.Vec3) -> f32 {
    if editor == nil do return 0
    return surface_weather.sample(&editor.surface_weather, position.x, position.z)
}

active_surface_weather_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    if editor == nil do return {}
    if driving_aircraft(editor) do return active_aircraft_body(editor).position
    if driving_car(editor) do return editor.car.position
    return editor.player.position
}

surface_weather_step :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || delta_seconds <= 0 do return
    UPDATES_PER_FRAME :: 4
    sky := atmosphere.sample(&editor.atmosphere)
    elapsed_per_cell := delta_seconds * f32(surface_weather.CELL_COUNT) / UPDATES_PER_FRAME
    for _ in 0 ..< UPDATES_PER_FRAME {
        index := editor.surface_weather.cursor % surface_weather.CELL_COUNT
        point := surface_weather.cell_position(&editor.surface_weather, index)
        ground := terrain.sample_surface_height(&editor.project, 0, point.x, point.y)
        position := third_person.Vec3{point.x, ground + .5, point.y}
        local := atmosphere_local_weather(editor, position)
        speed := f32(math.sqrt(f64(local.wind[0] * local.wind[0] + local.wind[2] * local.wind[2])))
        surface_weather.step_cell(
            &editor.surface_weather,
            index,
            local.precipitation,
            sky.daylight,
            speed,
            local.temperature_tendency,
            elapsed_per_cell,
        )
        editor.surface_weather.cursor = (index + 1) % surface_weather.CELL_COUNT
    }
}

aircraft_local_airflow :: proc(editor: ^Editor, body: ^flight.Body_State) -> flight.Vec3 {
    if editor == nil || body == nil do return {}
    local := atmosphere_local_weather(editor, body.position)
    return {local.wind[0], local.wind[1], local.wind[2]}
}

aircraft_wind_buffet :: proc(editor: ^Editor) -> f32 {
    if editor == nil || active_aircraft_grounded(editor) || active_aircraft_crashed(editor) do return 0
    body := active_aircraft_body(editor)
    local := atmosphere.sample_at(
        &editor.atmosphere,
        {body.position.x, body.position.y, body.position.z},
        body.position.y,
    )
    wind_x, wind_z := local.wind[0], local.wind[2]
    weather_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
    lateral := wind_audio.apparent_lateral_direction(
        wind_x,
        wind_z,
        body.velocity.x,
        body.velocity.z,
        editor.camera.yaw_radians,
    )
    return air_effects.buffet_strength(
        weather_speed,
        lateral,
        max(local.severity, local.gust_strength),
        editor.atmosphere.schedule.elapsed_seconds,
    )
}

postale_flyby_shake :: proc(editor: ^Editor) -> f32 {
    if editor == nil || editor.aircraft.active != .Postale || editor.postale.grounded || editor.postale.crashed {
        return 0
    }
    speed_strength := clamp((postale_game.selected_airspeed(&editor.postale) - 32) / 30, 0, 1)
    if speed_strength <= 0 do return 0
    position := editor.postale.body.position
    strongest := f32(0)
    for structure in editor.project.structures[:editor.project.structure_count] {
        longest := max(max(structure.width, structure.depth), structure.height)
        if longest < 18 do continue
        center := flight.Vec3{structure.center_x, structure.base_y + structure.height * .5, structure.center_z}
        extent := flight.Vec3{structure.width * .5, structure.height * .5, structure.depth * .5}
        response_range := 10 + clamp(longest * .08, 2, 18)
        proximity := chase_camera.box_flyby_strength(position, center, extent, structure.rotation, response_range)
        size_strength := clamp((longest - 12) / 48, .25, 1)
        strongest = max(strongest, proximity * size_strength)
    }
    return strongest * speed_strength
}

rondine_drift_shake :: proc(editor: ^Editor) -> f32 {
    if editor == nil || editor.aircraft.active != .Rondine || editor.rondine.crashed do return 0
    return editor.rondine.telemetry.drift_intensity * .42
}

active_aircraft_ground_clearance :: proc(editor: ^Editor) -> f32 {
    if editor != nil && editor.aircraft.active == .Rondine do return rondine_game.GROUND_CLEARANCE
    if editor != nil && editor.aircraft.active != .Postale do return editor.libellula.tuning.ground_clearance
    return postale_game.GROUND_CLEARANCE
}

libellula_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    runway_x, runway_z := terrain.default_runway_center_for_project(&editor.project, 1)
    x := runway_x + half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET + 12
    z := runway_z + 8
    return {x, terrain.sample_surface_height(&editor.project, 0, x, z) + 2.1, z}
}

rondine_spawn_position :: proc(editor: ^Editor) -> flight.Vec3 {
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    center := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    offset := half_extent * terrain.DEFAULT_ISLAND_RADIUS * .92
    x, z := center - offset, center - offset
    return {x, editor.project.sea_level + rondine_game.GROUND_CLEARANCE, z}
}
