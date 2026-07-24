package main

import atmosphere "../packages/atmosphere"
import flight "../packages/flight"
import im "../packages/imgui"
import postale_game "../packages/postale"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import tweak_package "../packages/tweak"
import vehicles "../packages/vehicles"
import "core:math"

TWEAK_FILE_PATH :: "adriatic.tweak.toml"
TWEAK_FILE_VERSION :: i64(1)

Tweak_Status :: enum {
    Defaults,
    Loaded,
    Saved,
    Save_Failed,
}

Terrain_Tweak :: struct {
    tool:      terrain.Tool,
    radius:    f32 `tweak:"range=0..400;1"`,
    strength:  f32 `tweak:"range=0..1;.01"`,
    sea_level: f32 `tweak:"range=-50..50;.1"`,
}

Vehicle_Tweak :: struct {
    interaction_radius: f32 `tweak:"range=0..20;.05"`,
    exit_distance:      f32 `tweak:"range=0..20;.05"`,
    locked:             bool,
}

Camera_Tweak :: struct {
    editor_camera:      third_person.Camera,
    editor_focus:       third_person.Vec3,
    player_camera:      third_person.Camera,
    flight_orbit_yaw:   f32,
    flight_orbit_pitch: f32,
}

World_Tweak :: struct {
    far_clip:              f32 `tweak:"range=100..50000;10"`,
    fog_start:             f32 `tweak:"range=0..50000;10"`,
    fog_end:               f32 `tweak:"range=1..50000;10"`,
    map_ocean_extent:      f32 `tweak:"range=100..50000;10"`,
    map_ocean_divisions:   int,
    editor_ocean_extent:   f32 `tweak:"range=100..50000;10"`,
    editor_ocean_divisions: int,
    map_ocean_depth:       f32 `tweak:"range=0..100;.01"`,
    editor_ocean_depth:    f32 `tweak:"range=0..100;.01"`,
}

Particle_CPU_Tweak :: struct {
    spawn_rate:             f32,
    origin_radius:          f32,
    radial_speed:           f32,
    radial_speed_variation: f32,
    lift_speed:             f32,
    lift_speed_variation:   f32,
    lifetime:               f32,
    lifetime_variation:     f32,
    size:                   f32,
    size_variation:         f32,
    gravity:                f32,
}

Particle_Vehicle_Tweak :: struct {
    dust_spawn_rate:          f32,
    dust_speed_divisor:       f32,
    dust_steering_divisor:    f32,
    dust_handbrake_bonus:     f32,
    dust_max_intensity:       f32,
    dust_spawn_threshold:     f32,
    dust_contact_spread:      f32,
    dust_height:              f32,
    dust_radial_speed:        f32,
    dust_intensity_speed:     f32,
    dust_lift:                f32,
    dust_lift_variation:      f32,
    dust_lifetime:            f32,
    dust_lifetime_variation:  f32,
    dust_size:                f32,
    dust_intensity_size:      f32,
    dust_lift_size:           f32,
    dust_gravity:             f32,
    exhaust_base_spawn_rate:  f32,
    exhaust_throttle_scale:   f32,
    exhaust_speed_divisor:    f32,
    exhaust_max_intensity:    f32,
    exhaust_intensity_rate:   f32,
    exhaust_spawn_threshold:  f32,
    exhaust_offset:           f32,
    exhaust_height:           f32,
    exhaust_forward_speed:    f32,
    exhaust_intensity_speed:  f32,
    exhaust_spread:           f32,
    exhaust_lift:             f32,
    exhaust_lift_variation:   f32,
    exhaust_lifetime:         f32,
    exhaust_lifetime_variation: f32,
    exhaust_size:             f32,
    exhaust_intensity_size:   f32,
    exhaust_lift_size:        f32,
    exhaust_gravity:          f32,
}

Particle_Wing_Tweak :: struct {
    airspeed_start:       f32,
    airspeed_range:       f32,
    wind_strength:        f32,
    spawn_rate:           f32,
    forward_speed:        f32,
    forward_jitter:       f32,
    wind_velocity:        f32,
    vertical_jitter:      f32,
    lifetime:             f32,
    lifetime_variation:   f32,
    wind_lifetime:        f32,
    size:                 f32,
    strength_size:        f32,
    wind_size:            f32,
    curve:                f32,
    curve_variation:      f32,
    gravity:              f32,
}

Particle_GPU_Tweak :: struct {
    center:                [3]f32,
    radius_min:            f32,
    radius_range:          f32,
    cycle_rate_min:        f32,
    cycle_rate_range:      f32,
    drift:                 f32,
    size_min:              f32,
    size_range:            f32,
    fade:                  f32,
    count:                 int,
    color_start:           [3]f32 `tweak:"widget=color"`,
    color_end:             [3]f32 `tweak:"widget=color"`,
}

Particle_Tweak :: struct {
    cpu_seed:     u32,
    vehicle_seed: u32,
    wing_seed:    u32,
    cpu:          Particle_CPU_Tweak,
    vehicle:      Particle_Vehicle_Tweak,
    wing:         Particle_Wing_Tweak,
    gpu:          Particle_GPU_Tweak,
}

Presentation_Tweak :: struct {
    terrain_water:     [4]f32 `tweak:"widget=color"`,
    terrain_sand:      [4]f32 `tweak:"widget=color"`,
    terrain_soil:      [4]f32 `tweak:"widget=color"`,
    terrain_grass:     [4]f32 `tweak:"widget=color"`,
    painted_threshold: f32 `tweak:"range=0..1;.01"`,
    sand_start:        f32 `tweak:"range=0..10;.01"`,
    land_blend:        f32 `tweak:"range=.01..10;.01"`,
    grass_start:       f32 `tweak:"range=0..20;.01"`,
    grass_blend:       f32 `tweak:"range=.01..20;.01"`,
    light_direction:   [3]f32,
    shade_base:        f32 `tweak:"range=0..2;.01"`,
    shade_strength:    f32 `tweak:"range=0..2;.01"`,
    shade_min:         f32 `tweak:"range=0..2;.01"`,
    shade_max:         f32 `tweak:"range=0..2;.01"`,
    height_shade:      f32 `tweak:"range=-1..1;.001"`,
}

Tweak_State :: struct {
    terrain:          Terrain_Tweak,
    atmosphere:       atmosphere.Atmosphere,
    player:           third_person.Config,
    camera:           Camera_Tweak,
    world:            World_Tweak,
    particles:        Particle_Tweak,
    car:              vehicles.Car_Drive_Tune,
    car_vehicle:      Vehicle_Tweak,
    postale_airframe: flight.Airframe,
    postale_runtime:  flight.Runtime,
    postale_tuning:   postale_game.Tuning,
    postale_vehicle:  Vehicle_Tweak,
    presentation:     Presentation_Tweak,
}

tweak_default_presentation :: proc() -> Presentation_Tweak {
    return {
        terrain_water = {26 / 255.0, 80 / 255.0, 104 / 255.0, 1},
        terrain_sand = {205 / 255.0, 183 / 255.0, 126 / 255.0, 1},
        terrain_soil = {145 / 255.0, 101 / 255.0, 61 / 255.0, 1},
        terrain_grass = {70 / 255.0, 133 / 255.0, 80 / 255.0, 1},
        painted_threshold = .5,
        sand_start = .18,
        land_blend = .72,
        grass_start = .9,
        grass_blend = 3.1,
        light_direction = {-.45, .85, -.3},
        shade_base = .48,
        shade_strength = .52,
        shade_min = .42,
        shade_max = 1.05,
        height_shade = .012,
    }
}

tweak_default_world :: proc() -> World_Tweak {
    return {
        far_clip               = 12000,
        fog_start              = 4500,
        fog_end                = 11000,
        map_ocean_extent       = 12000,
        map_ocean_divisions    = 48,
        editor_ocean_extent    = 15000,
        editor_ocean_divisions = 32,
        map_ocean_depth        = .08,
        editor_ocean_depth     = 2,
    }
}

tweak_default_particles :: proc() -> Particle_Tweak {
    return {
        cpu_seed = 0x9e3779b9,
        vehicle_seed = 0x72b7e4a1,
        wing_seed = 0x1f123bb5,
        cpu = {
            spawn_rate             = 72,
            origin_radius          = 1.8,
            radial_speed           = .35,
            radial_speed_variation = .55,
            lift_speed             = .45,
            lift_speed_variation   = .75,
            lifetime               = 1.2,
            lifetime_variation     = 1.7,
            size                   = .08,
            size_variation         = .14,
            gravity                = .36,
        },
        vehicle = {
            dust_spawn_rate            = 48,
            dust_speed_divisor         = 12,
            dust_steering_divisor      = 18,
            dust_handbrake_bonus       = .65,
            dust_max_intensity         = 1.5,
            dust_spawn_threshold       = .18,
            dust_contact_spread        = .18,
            dust_height                = .045,
            dust_radial_speed          = .35,
            dust_intensity_speed       = 1,
            dust_lift                  = .18,
            dust_lift_variation        = .32,
            dust_lifetime              = .28,
            dust_lifetime_variation    = .42,
            dust_size                  = .08,
            dust_intensity_size        = .08,
            dust_lift_size             = .10,
            dust_gravity               = .22,
            exhaust_base_spawn_rate    = 4,
            exhaust_throttle_scale     = .7,
            exhaust_speed_divisor      = 32,
            exhaust_max_intensity      = 1,
            exhaust_intensity_rate     = 22,
            exhaust_spawn_threshold    = .02,
            exhaust_offset             = 1.92,
            exhaust_height             = .42,
            exhaust_forward_speed      = .25,
            exhaust_intensity_speed    = .45,
            exhaust_spread             = .22,
            exhaust_lift               = .08,
            exhaust_lift_variation     = .15,
            exhaust_lifetime           = .34,
            exhaust_lifetime_variation = .42,
            exhaust_size               = .055,
            exhaust_intensity_size     = .045,
            exhaust_lift_size          = .06,
            exhaust_gravity            = .06,
        },
        wing = {
            airspeed_start      = 12,
            airspeed_range      = 34,
            wind_strength       = .025,
            spawn_rate          = 72,
            forward_speed       = .22,
            forward_jitter      = .025,
            wind_velocity       = .18,
            vertical_jitter     = .08,
            lifetime            = .55,
            lifetime_variation  = .55,
            wind_lifetime       = .02,
            size                = .09,
            strength_size       = .12,
            wind_size           = .004,
            curve               = .7,
            curve_variation     = .3,
            gravity             = .025,
        },
        gpu = {
            center           = {1300, 6, 1300},
            radius_min       = .6,
            radius_range     = 2.4,
            cycle_rate_min   = .18,
            cycle_rate_range = .22,
            drift            = .35,
            size_min         = .055,
            size_range       = .12,
            fade              = .25,
            count             = 512,
            color_start      = {.95, .65, .22},
            color_end        = {1, .92, .55},
        },
    }
}

tweak_default_state :: proc() -> Tweak_State {
    return {
        terrain = {tool = .Raise, radius = 48, strength = .10, sea_level = 0},
        atmosphere = atmosphere.new(0x41c10),
        player = third_person.default_config(),
        camera = {
            editor_camera = {yaw_radians = math.PI * .25, pitch_radians = .58, distance = 900},
            editor_focus = {
                x = terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET,
                z = terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET,
            },
            player_camera = third_person.default_camera(),
        },
        world = tweak_default_world(),
        particles = tweak_default_particles(),
        car = vehicles.CAR_DRIVE_SEDAN_TUNE,
        car_vehicle = {interaction_radius = 3, exit_distance = 1.45},
        postale_airframe = flight.postale_airframe(),
        postale_runtime = flight.default_runtime(),
        postale_tuning = postale_game.default_tuning(),
        postale_vehicle = {interaction_radius = 2.5, exit_distance = 2.2},
        presentation = tweak_default_presentation(),
    }
}

tweak_sync_from_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.tweak.terrain = {
        tool      = editor.tool,
        radius    = editor.radius,
        strength  = editor.strength,
        sea_level = editor.project.sea_level,
    }
    editor.tweak.atmosphere = editor.atmosphere
    editor.tweak.camera.editor_camera = editor.editor_camera
    editor.tweak.camera.editor_focus = editor.editor_focus
    editor.tweak.camera.player_camera = editor.camera
    editor.tweak.camera.flight_orbit_yaw = editor.flight_camera.orbit_yaw
    editor.tweak.camera.flight_orbit_pitch = editor.flight_camera.orbit_pitch
    editor.tweak.car_vehicle = {
        interaction_radius = editor.car.interaction_radius,
        exit_distance      = editor.car.exit_distance,
        locked             = editor.car.locked,
    }
    editor.tweak.postale_airframe = editor.postale.airframe
    editor.tweak.postale_runtime = editor.postale.flight_runtime
    editor.tweak.postale_tuning = editor.postale.tuning
    editor.tweak.postale_vehicle = {
        interaction_radius = editor.postale.vehicle.interaction_radius,
        exit_distance      = editor.postale.vehicle.exit_distance,
        locked             = editor.postale.vehicle.locked,
    }
}

tweak_apply_to_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    state := &editor.tweak
    editor.tool = state.terrain.tool
    editor.radius = clamp(state.terrain.radius, terrain.BASE_CELL_SIZE, 400)
    editor.strength = clamp(state.terrain.strength, 0, 1)
    editor.project.sea_level = state.terrain.sea_level
    editor.atmosphere = state.atmosphere
    editor.camera = state.camera.player_camera
    editor.editor_camera = state.camera.editor_camera
    editor.editor_focus = state.camera.editor_focus
    editor.flight_camera.orbit_yaw = state.camera.flight_orbit_yaw
    editor.flight_camera.orbit_pitch = clamp(state.camera.flight_orbit_pitch, -.75, .75)
    editor.car.interaction_radius = state.car_vehicle.interaction_radius
    editor.car.exit_distance = state.car_vehicle.exit_distance
    editor.car.locked = state.car_vehicle.locked
    editor.postale.airframe = state.postale_airframe
    editor.postale.flight_runtime = state.postale_runtime
    editor.postale.tuning = state.postale_tuning
    editor.postale.vehicle.interaction_radius = state.postale_vehicle.interaction_radius
    editor.postale.vehicle.exit_distance = state.postale_vehicle.exit_distance
    editor.postale.vehicle.locked = state.postale_vehicle.locked
}

tweak_save_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    tweak_sync_from_editor(editor)
    if err := tweak_package.save(TWEAK_FILE_PATH, TWEAK_FILE_VERSION, &editor.tweak); err != nil {
        editor.tweak_status = .Save_Failed
    } else {
        editor.tweak_status = .Saved
    }
}

tweak_load_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    state := tweak_default_state()
    result := tweak_package.load(TWEAK_FILE_PATH, TWEAK_FILE_VERSION, &state, "Adriatic tweaks")
    editor.tweak = state
    tweak_apply_to_editor(editor)
    editor.tweak_status = result.loaded_sections > 0 ? .Loaded : .Defaults
    tweak_package.destroy_load_result(&result)
}

tweak_drag_f32 :: proc(label: cstring, value: ^f32, lower, upper, speed: f32) -> bool {
    return im.DragFloat(label, value, speed, lower, upper, "%.3f", im.SliderFlags_AlwaysClamp)
}

tweak_draw_terrain :: proc(editor: ^Editor) {
    state := &editor.tweak.terrain
    im.TextUnformatted("Brush")
    if im.RadioButton("Raise", state.tool == .Raise) do state.tool = .Raise
    im.SameLine()
    if im.RadioButton("Smooth", state.tool == .Smooth) do state.tool = .Smooth
    im.SameLine()
    if im.RadioButton("Paint", state.tool == .Paint) do state.tool = .Paint
    tweak_drag_f32("Radius", &state.radius, terrain.BASE_CELL_SIZE, 400, 1)
    tweak_drag_f32("Strength", &state.strength, 0, 1, .01)
    tweak_drag_f32("Sea level", &state.sea_level, -50, 50, .1)
    im.SeparatorText("Project")
    im.Text("Revision: %d", editor.project.revision)
    im.Text("Clipmap levels: %d", terrain.CLIPMAP_LEVELS)
    im.Text("World size: %.0f m", terrain.WORLD_SIZE_METERS)
}

tweak_draw_atmosphere :: proc(editor: ^Editor) {
    a := &editor.tweak.atmosphere
    im.SliderFloat("World minutes", &a.world_minutes, 0, atmosphere.DAY_MINUTES, "%.1f", im.SliderFlags_AlwaysClamp)
    im.InputScalar("Seed", im.DataType.U32, rawptr(&a.seed), nil, nil, "%u")
    im.Checkbox("Paused", &a.paused)
    im.TextUnformatted("Weather override")
    if im.RadioButton("Automatic", a.override == .Automatic) do a.override = .Automatic
    im.SameLine()
    if im.RadioButton("Clear", a.override == .Clear) do a.override = .Clear
    im.SameLine()
    if im.RadioButton("Windy", a.override == .Windy) do a.override = .Windy
    im.SameLine()
    if im.RadioButton("Storm", a.override == .Storm) do a.override = .Storm
    im.SeparatorText("Current weather")
    tweak_drag_f32("Cloud cover", &a.weather.cloud_cover, 0, 1, .01)
    tweak_drag_f32("Precipitation", &a.weather.precipitation, 0, 1, .01)
    tweak_drag_f32("Haze", &a.weather.haze, 0, 1, .01)
    tweak_drag_f32("Severity", &a.weather.severity, 0, 1, .01)
    im.DragFloat2("Wind", &a.weather.wind, .05, -100, 100, "%.2f", im.SliderFlags_AlwaysClamp)
}

tweak_draw_player :: proc(editor: ^Editor) {
    c := &editor.tweak.player
    tweak_drag_f32("Move speed", &c.move_speed, 0, 100, .1)
    tweak_drag_f32("Ground acceleration", &c.ground_acceleration, 0, 200, .5)
    tweak_drag_f32("Air acceleration", &c.air_acceleration, 0, 200, .5)
    tweak_drag_f32("Jump speed", &c.jump_speed, 0, 50, .1)
    tweak_drag_f32("Gravity", &c.gravity, 0, 100, .1)
    im.SeparatorText("Runtime")
    im.Text("Position: %.2f %.2f %.2f", editor.player.position.x, editor.player.position.y, editor.player.position.z)
    im.Text("Grounded: %s", editor.player.grounded ? "yes" : "no")
}

tweak_draw_camera :: proc(editor: ^Editor) {
    c := &editor.tweak.camera
    im.SeparatorText("Editor camera")
    tweak_drag_f32("Editor yaw", &c.editor_camera.yaw_radians, -math.PI * 2, math.PI * 2, .01)
    tweak_drag_f32("Editor pitch", &c.editor_camera.pitch_radians, -.85, 1.2, .01)
    tweak_drag_f32("Editor distance", &c.editor_camera.distance, 80, 5000, 1)
    tweak_drag_f32("Editor height", &c.editor_camera.height, -100, 100, .1)
    tweak_drag_f32("Editor focus X", &c.editor_focus.x, -10000, 10000, 1)
    tweak_drag_f32("Editor focus Y", &c.editor_focus.y, -10000, 10000, 1)
    tweak_drag_f32("Editor focus Z", &c.editor_focus.z, -10000, 10000, 1)
    im.SeparatorText("Player camera")
    tweak_drag_f32("Player yaw", &c.player_camera.yaw_radians, -math.PI * 2, math.PI * 2, .01)
    tweak_drag_f32("Player pitch", &c.player_camera.pitch_radians, -.85, 1.2, .01)
    tweak_drag_f32("Player distance", &c.player_camera.distance, 3, 12, .05)
    tweak_drag_f32("Player height", &c.player_camera.height, 0, 10, .05)
    im.SeparatorText("Flight orbit")
    tweak_drag_f32("Flight yaw", &c.flight_orbit_yaw, -math.PI * 2, math.PI * 2, .01)
    tweak_drag_f32("Flight pitch", &c.flight_orbit_pitch, -.75, .75, .01)
}

tweak_draw_world :: proc(editor: ^Editor) {
    w := &editor.tweak.world
    tweak_drag_f32("Far clip", &w.far_clip, 100, 50000, 10)
    tweak_drag_f32("Fog start", &w.fog_start, 0, 50000, 10)
    tweak_drag_f32("Fog end", &w.fog_end, 1, 50000, 10)
    im.SeparatorText("Map ocean")
    tweak_drag_f32("Map extent", &w.map_ocean_extent, 100, 50000, 10)
    im.InputScalar("Map divisions", im.DataType.S32, rawptr(&w.map_ocean_divisions), nil, nil, "%d")
    tweak_drag_f32("Map depth", &w.map_ocean_depth, 0, 100, .01)
    im.SeparatorText("Editor ocean")
    tweak_drag_f32("Editor extent", &w.editor_ocean_extent, 100, 50000, 10)
    im.InputScalar("Editor divisions", im.DataType.S32, rawptr(&w.editor_ocean_divisions), nil, nil, "%d")
    tweak_drag_f32("Editor depth", &w.editor_ocean_depth, 0, 100, .01)
}

tweak_draw_particles :: proc(editor: ^Editor) {
    p := &editor.tweak.particles
    im.InputScalar("CPU seed", im.DataType.U32, rawptr(&p.cpu_seed), nil, nil, "%u")
    im.InputScalar("Vehicle seed", im.DataType.U32, rawptr(&p.vehicle_seed), nil, nil, "%u")
    im.InputScalar("Wing seed", im.DataType.U32, rawptr(&p.wing_seed), nil, nil, "%u")
    im.SeparatorText("CPU particles")
    tweak_drag_f32("CPU spawn rate", &p.cpu.spawn_rate, 0, 1000, 1)
    tweak_drag_f32("CPU origin radius", &p.cpu.origin_radius, 0, 20, .01)
    tweak_drag_f32("CPU radial speed", &p.cpu.radial_speed, 0, 20, .01)
    tweak_drag_f32("CPU radial variation", &p.cpu.radial_speed_variation, 0, 20, .01)
    tweak_drag_f32("CPU lift speed", &p.cpu.lift_speed, 0, 20, .01)
    tweak_drag_f32("CPU lift variation", &p.cpu.lift_speed_variation, 0, 20, .01)
    tweak_drag_f32("CPU lifetime", &p.cpu.lifetime, 0, 30, .01)
    tweak_drag_f32("CPU lifetime variation", &p.cpu.lifetime_variation, 0, 30, .01)
    tweak_drag_f32("CPU size", &p.cpu.size, 0, 2, .001)
    tweak_drag_f32("CPU size variation", &p.cpu.size_variation, 0, 2, .001)
    tweak_drag_f32("CPU gravity", &p.cpu.gravity, 0, 20, .01)

    im.SeparatorText("Vehicle dust")
    tweak_drag_f32("Dust spawn rate", &p.vehicle.dust_spawn_rate, 0, 500, 1)
    tweak_drag_f32("Dust speed divisor", &p.vehicle.dust_speed_divisor, .01, 200, .1)
    tweak_drag_f32("Dust steering divisor", &p.vehicle.dust_steering_divisor, .01, 200, .1)
    tweak_drag_f32("Dust handbrake bonus", &p.vehicle.dust_handbrake_bonus, 0, 5, .01)
    tweak_drag_f32("Dust max intensity", &p.vehicle.dust_max_intensity, 0, 10, .01)
    tweak_drag_f32("Dust spawn threshold", &p.vehicle.dust_spawn_threshold, 0, 2, .01)
    tweak_drag_f32("Dust contact spread", &p.vehicle.dust_contact_spread, 0, 5, .01)
    tweak_drag_f32("Dust height", &p.vehicle.dust_height, 0, 5, .01)
    tweak_drag_f32("Dust radial speed", &p.vehicle.dust_radial_speed, 0, 10, .01)
    tweak_drag_f32("Dust intensity speed", &p.vehicle.dust_intensity_speed, 0, 10, .01)
    tweak_drag_f32("Dust lift", &p.vehicle.dust_lift, 0, 10, .01)
    tweak_drag_f32("Dust lift variation", &p.vehicle.dust_lift_variation, 0, 10, .01)
    tweak_drag_f32("Dust lifetime", &p.vehicle.dust_lifetime, 0, 10, .01)
    tweak_drag_f32("Dust lifetime variation", &p.vehicle.dust_lifetime_variation, 0, 10, .01)
    tweak_drag_f32("Dust size", &p.vehicle.dust_size, 0, 2, .001)
    tweak_drag_f32("Dust intensity size", &p.vehicle.dust_intensity_size, 0, 2, .001)
    tweak_drag_f32("Dust lift size", &p.vehicle.dust_lift_size, 0, 2, .001)
    tweak_drag_f32("Dust gravity", &p.vehicle.dust_gravity, 0, 20, .01)

    im.SeparatorText("Vehicle exhaust")
    tweak_drag_f32("Exhaust base spawn", &p.vehicle.exhaust_base_spawn_rate, 0, 100, 1)
    tweak_drag_f32("Exhaust throttle scale", &p.vehicle.exhaust_throttle_scale, 0, 5, .01)
    tweak_drag_f32("Exhaust speed divisor", &p.vehicle.exhaust_speed_divisor, .01, 200, .1)
    tweak_drag_f32("Exhaust max intensity", &p.vehicle.exhaust_max_intensity, 0, 5, .01)
    tweak_drag_f32("Exhaust intensity rate", &p.vehicle.exhaust_intensity_rate, 0, 100, 1)
    tweak_drag_f32("Exhaust spawn threshold", &p.vehicle.exhaust_spawn_threshold, 0, 1, .01)
    tweak_drag_f32("Exhaust offset", &p.vehicle.exhaust_offset, 0, 10, .01)
    tweak_drag_f32("Exhaust height", &p.vehicle.exhaust_height, 0, 5, .01)
    tweak_drag_f32("Exhaust forward speed", &p.vehicle.exhaust_forward_speed, 0, 10, .01)
    tweak_drag_f32("Exhaust intensity speed", &p.vehicle.exhaust_intensity_speed, 0, 10, .01)
    tweak_drag_f32("Exhaust spread", &p.vehicle.exhaust_spread, 0, 5, .01)
    tweak_drag_f32("Exhaust lift", &p.vehicle.exhaust_lift, 0, 5, .01)
    tweak_drag_f32("Exhaust lift variation", &p.vehicle.exhaust_lift_variation, 0, 5, .01)
    tweak_drag_f32("Exhaust lifetime", &p.vehicle.exhaust_lifetime, 0, 10, .01)
    tweak_drag_f32("Exhaust lifetime variation", &p.vehicle.exhaust_lifetime_variation, 0, 10, .01)
    tweak_drag_f32("Exhaust size", &p.vehicle.exhaust_size, 0, 2, .001)
    tweak_drag_f32("Exhaust intensity size", &p.vehicle.exhaust_intensity_size, 0, 2, .001)
    tweak_drag_f32("Exhaust lift size", &p.vehicle.exhaust_lift_size, 0, 2, .001)
    tweak_drag_f32("Exhaust gravity", &p.vehicle.exhaust_gravity, 0, 20, .01)

    im.SeparatorText("Wing trails")
    tweak_drag_f32("Trail airspeed start", &p.wing.airspeed_start, 0, 200, .1)
    tweak_drag_f32("Trail airspeed range", &p.wing.airspeed_range, .01, 200, .1)
    tweak_drag_f32("Trail wind strength", &p.wing.wind_strength, 0, 2, .001)
    tweak_drag_f32("Trail spawn rate", &p.wing.spawn_rate, 0, 500, 1)
    tweak_drag_f32("Trail forward speed", &p.wing.forward_speed, 0, 10, .01)
    tweak_drag_f32("Trail forward jitter", &p.wing.forward_jitter, 0, 2, .001)
    tweak_drag_f32("Trail wind velocity", &p.wing.wind_velocity, 0, 10, .01)
    tweak_drag_f32("Trail vertical jitter", &p.wing.vertical_jitter, 0, 2, .001)
    tweak_drag_f32("Trail lifetime", &p.wing.lifetime, 0, 10, .01)
    tweak_drag_f32("Trail lifetime variation", &p.wing.lifetime_variation, 0, 10, .01)
    tweak_drag_f32("Trail wind lifetime", &p.wing.wind_lifetime, 0, 2, .001)
    tweak_drag_f32("Trail size", &p.wing.size, 0, 2, .001)
    tweak_drag_f32("Trail strength size", &p.wing.strength_size, 0, 2, .001)
    tweak_drag_f32("Trail wind size", &p.wing.wind_size, 0, 2, .001)
    tweak_drag_f32("Trail curve", &p.wing.curve, 0, 5, .01)
    tweak_drag_f32("Trail curve variation", &p.wing.curve_variation, 0, 5, .01)
    tweak_drag_f32("Trail gravity", &p.wing.gravity, 0, 5, .01)

    im.SeparatorText("GPU particles")
    im.DragFloat3("GPU center", &p.gpu.center, 1, -50000, 50000, "%.1f", im.SliderFlags_AlwaysClamp)
    tweak_drag_f32("GPU radius", &p.gpu.radius_min, 0, 100, .01)
    tweak_drag_f32("GPU radius range", &p.gpu.radius_range, 0, 100, .01)
    tweak_drag_f32("GPU cycle rate", &p.gpu.cycle_rate_min, 0, 10, .001)
    tweak_drag_f32("GPU cycle variation", &p.gpu.cycle_rate_range, 0, 10, .001)
    tweak_drag_f32("GPU drift", &p.gpu.drift, 0, 10, .01)
    tweak_drag_f32("GPU size", &p.gpu.size_min, 0, 2, .001)
    tweak_drag_f32("GPU size range", &p.gpu.size_range, 0, 2, .001)
    tweak_drag_f32("GPU fade", &p.gpu.fade, 0, 1, .01)
    im.InputScalar("GPU count", im.DataType.S32, rawptr(&p.gpu.count), nil, nil, "%d")
    im.DragFloat3("GPU color start", &p.gpu.color_start, .01, 0, 1, "%.2f", im.SliderFlags_AlwaysClamp)
    im.DragFloat3("GPU color end", &p.gpu.color_end, .01, 0, 1, "%.2f", im.SliderFlags_AlwaysClamp)
}

tweak_draw_car :: proc(editor: ^Editor) {
    t := &editor.tweak.car
    tweak_drag_f32("Acceleration", &t.acceleration, 0, 100, .1)
    tweak_drag_f32("Brake", &t.brake, 0, 100, .1)
    tweak_drag_f32("Reverse acceleration", &t.reverse_acceleration, 0, 100, .1)
    tweak_drag_f32("Max forward", &t.max_forward, .1, 200, .1)
    tweak_drag_f32("Max reverse", &t.max_reverse, .1, 100, .1)
    tweak_drag_f32("Steering response", &t.steering_response, 0, 50, .1)
    tweak_drag_f32("Yaw response", &t.yaw_response, 0, 50, .1)
    tweak_drag_f32("Lateral grip", &t.lateral_grip, 0, 50, .1)
    tweak_drag_f32("Handbrake grip", &t.handbrake_grip, 0, 50, .1)
    tweak_drag_f32("Coast deceleration", &t.coast_deceleration, 0, 50, .1)
    im.SeparatorText("Interaction")
    tweak_drag_f32("Enter radius", &editor.tweak.car_vehicle.interaction_radius, 0, 20, .05)
    tweak_drag_f32("Exit distance", &editor.tweak.car_vehicle.exit_distance, 0, 20, .05)
    im.Checkbox("Locked", &editor.tweak.car_vehicle.locked)
    im.SeparatorText("Diagnostics")
    im.Text("Speed: %.2f", vehicles.car_drive_speed(editor.car_drive))
    im.Text("Yaw rate: %.2f", editor.car_drive.yaw_rate)
}

tweak_draw_postale :: proc(editor: ^Editor) {
    a := &editor.tweak.postale_airframe
    im.Text("Layout: fixed wing (%d)", a.flight_layout)
    tweak_drag_f32("Mass kg", &a.mass_kg, 1, 50000, 1)
    tweak_drag_f32("Maximum gross mass kg", &a.maximum_gross_mass_kg, 1, 50000, 1)
    tweak_drag_f32("Wing area", &a.wing_area, .1, 500, .1)
    tweak_drag_f32("Lift scale", &a.lift_scale, 0, 10, .01)
    tweak_drag_f32("Drag scale", &a.drag_scale, 0, 10, .01)
    tweak_drag_f32("Stall speed", &a.stall_speed, 1, 200, .1)
    tweak_drag_f32("Maximum speed", &a.maximum_speed, 1, 300, .1)
    tweak_drag_f32("Power per engine kw", &a.rated_power_per_engine_kw, 0, 5000, 1)
    tweak_drag_f32("Propeller efficiency", &a.propeller_efficiency, 0, 1, .01)
    tweak_drag_f32("Static thrust", &a.static_thrust_per_engine, 0, 100000, 10)
    tweak_drag_f32("Engine count", &a.engine_count, 1, 8, .1)
    tweak_drag_f32("Wing incidence deg", &a.wing_incidence_degrees, -30, 30, .1)
    tweak_drag_f32("Lift curve slope", &a.lift_curve_slope_per_degree, 0, 1, .001)
    tweak_drag_f32("Zero lift angle deg", &a.zero_lift_angle_degrees, -30, 30, .1)
    tweak_drag_f32("Critical angle deg", &a.critical_angle_degrees, 0, 90, .1)
    tweak_drag_f32("Negative critical angle deg", &a.negative_critical_angle_degrees, -90, 0, .1)
    tweak_drag_f32("Post stall angle deg", &a.post_stall_angle_degrees, 0, 120, .1)
    tweak_drag_f32("Post stall lift", &a.post_stall_lift_coefficient, 0, 2, .01)
    tweak_drag_f32("Induced drag", &a.induced_drag_factor, 0, 1, .001)
    tweak_drag_f32("Trim angle deg", &a.trim_angle_of_attack_degrees, -30, 30, .1)
    tweak_drag_f32("Pitch stability", &a.pitch_stability, 0, 1000000, 100)
    tweak_drag_f32("Pitch damping", &a.pitch_damping, 0, 1000000, 100)
    tweak_drag_f32("Roll stability", &a.roll_stability, 0, 1000000, 100)
    tweak_drag_f32("Roll damping", &a.roll_damping, 0, 1000000, 100)
    tweak_drag_f32("Yaw stability", &a.yaw_stability, 0, 1000000, 100)
    tweak_drag_f32("Yaw damping", &a.yaw_damping, 0, 1000000, 100)
    tweak_drag_f32("Pitch control", &a.pitch_control_scale, 0, 3, .01)
    tweak_drag_f32("Roll control", &a.roll_control_scale, 0, 3, .01)
    tweak_drag_f32("Yaw control", &a.yaw_control_scale, 0, 3, .01)
    im.Checkbox("Water capable", &a.water_capable)
    tweak_drag_f32("Planing start", &a.water_planing_start_speed, 0, 100, .1)
    tweak_drag_f32("Planing full", &a.water_planing_full_speed, 0, 100, .1)
    tweak_drag_f32("Planing reference", &a.water_planing_reference_speed, 0, 100, .1)
    tweak_drag_f32("Water plow drag", &a.water_plow_drag_scale, 0, 10, .01)
    im.SeparatorText("Runtime modifiers")
    tweak_drag_f32("Engine output", &editor.tweak.postale_runtime.engine_output, 0, 1, .01)
    tweak_drag_f32("Control authority", &editor.tweak.postale_runtime.control_authority, 0, 2, .01)
    tweak_drag_f32("Drag multiplier", &editor.tweak.postale_runtime.drag_multiplier, 0, 5, .01)
    tweak_drag_f32("Stall speed modifier", &editor.tweak.postale_runtime.stall_speed_modifier, .1, 2, .01)
    im.Checkbox("Controls damaged", &editor.tweak.postale_runtime.controls_damaged)
    im.SeparatorText("Safety")
    tweak_drag_f32("Ground clearance", &editor.tweak.postale_tuning.ground_clearance, 0, 5, .01)
    tweak_drag_f32("Safe touchdown speed", &editor.tweak.postale_tuning.safe_touchdown_speed, 0, 50, .1)
    tweak_drag_f32("Safe bank radians", &editor.tweak.postale_tuning.safe_bank_radians, 0, math.PI, .01)
    tweak_drag_f32("Safe exit speed", &editor.tweak.postale_tuning.safe_exit_speed, 0, 20, .1)
    tweak_drag_f32("Takeoff stall scale", &editor.tweak.postale_tuning.takeoff_stall_speed_scale, .1, 1.5, .01)
    im.SeparatorText("Controls")
    tweak_drag_f32("Throttle up rate", &editor.tweak.postale_tuning.throttle_up_rate, 0, 20, .01)
    tweak_drag_f32("Throttle down rate", &editor.tweak.postale_tuning.throttle_down_rate, 0, 20, .01)
    tweak_drag_f32("Pitch increase rate", &editor.tweak.postale_tuning.pitch_rate_increase, 0, 50, .01)
    tweak_drag_f32("Pitch decrease rate", &editor.tweak.postale_tuning.pitch_rate_decrease, 0, 50, .01)
    tweak_drag_f32("Roll increase rate", &editor.tweak.postale_tuning.roll_rate_increase, 0, 50, .01)
    tweak_drag_f32("Roll decrease rate", &editor.tweak.postale_tuning.roll_rate_decrease, 0, 50, .01)
    tweak_drag_f32("Yaw increase rate", &editor.tweak.postale_tuning.yaw_rate_increase, 0, 50, .01)
    tweak_drag_f32("Yaw decrease rate", &editor.tweak.postale_tuning.yaw_rate_decrease, 0, 50, .01)
    tweak_drag_f32("Flap response", &editor.tweak.postale_tuning.flap_response, 0, 20, .01)
    tweak_drag_f32("Flap auto throttle", &editor.tweak.postale_tuning.flap_auto_throttle, 0, 1, .01)
    tweak_drag_f32("Flap auto speed", &editor.tweak.postale_tuning.flap_auto_speed, 0, 200, .1)
    im.SeparatorText("Ground and takeoff")
    tweak_drag_f32("Ground brake", &editor.tweak.postale_tuning.ground_brake, 0, 20, .01)
    tweak_drag_f32("Ground coast", &editor.tweak.postale_tuning.ground_coast, 0, 20, .01)
    tweak_drag_f32("Ground steer fast", &editor.tweak.postale_tuning.ground_steer_fast, 0, 20, .01)
    tweak_drag_f32("Ground steer slow", &editor.tweak.postale_tuning.ground_steer_slow, 0, 20, .01)
    tweak_drag_f32("Takeoff throttle", &editor.tweak.postale_tuning.takeoff_throttle, 0, 1, .01)
    tweak_drag_f32("Takeoff speed scale", &editor.tweak.postale_tuning.takeoff_speed_scale, 0, 2, .01)
    tweak_drag_f32("Takeoff vertical assist", &editor.tweak.postale_tuning.takeoff_vertical_assist, 0, 20, .01)
    im.SeparatorText("Propeller")
    tweak_drag_f32("Propeller base rate", &editor.tweak.postale_tuning.propeller_base_rate, 0, 50, .01)
    tweak_drag_f32("Propeller throttle rate", &editor.tweak.postale_tuning.propeller_throttle_rate, 0, 100, .1)
    im.SeparatorText("Diagnostics")
    im.Text("Airspeed: %.2f", editor.postale.telemetry.airspeed)
    im.Text("AoA: %.2f deg", editor.postale.telemetry.angle_of_attack_degrees)
    im.Text("Stalling: %s", editor.postale.telemetry.is_stalling ? "yes" : "no")
}

tweak_draw_presentation :: proc(editor: ^Editor) {
    p := &editor.tweak.presentation
    im.ColorEdit4("Water", &p.terrain_water)
    im.ColorEdit4("Sand", &p.terrain_sand)
    im.ColorEdit4("Soil", &p.terrain_soil)
    im.ColorEdit4("Grass", &p.terrain_grass)
    tweak_drag_f32("Painted threshold", &p.painted_threshold, 0, 1, .01)
    tweak_drag_f32("Sand start", &p.sand_start, 0, 10, .01)
    tweak_drag_f32("Sand/soil blend", &p.land_blend, .01, 10, .01)
    tweak_drag_f32("Grass start", &p.grass_start, 0, 20, .01)
    tweak_drag_f32("Soil/grass blend", &p.grass_blend, .01, 20, .01)
    im.DragFloat3("Light direction", &p.light_direction, .01, -1, 1, "%.2f", im.SliderFlags_AlwaysClamp)
    tweak_drag_f32("Shade base", &p.shade_base, 0, 2, .01)
    tweak_drag_f32("Shade strength", &p.shade_strength, 0, 2, .01)
    tweak_drag_f32("Shade minimum", &p.shade_min, 0, 2, .01)
    tweak_drag_f32("Shade maximum", &p.shade_max, 0, 2, .01)
    tweak_drag_f32("Height shade", &p.height_shade, -1, 1, .001)
}

imgui_draw_tweaks :: proc(editor: ^Editor) {
    if editor == nil do return
    tweak_sync_from_editor(editor)
    im.SetNextWindowPos({24, 150}, im.Cond.Always)
    im.SetNextWindowSize({460, 650}, im.Cond.Always)
    if im.Begin("Adriatic Tweaks") {
        if im.Button("Save tweaks") do tweak_save_editor(editor)
        im.SameLine()
        if im.Button("Load tweaks") do tweak_load_editor(editor)
        im.SameLine()
        switch editor.tweak_status {
        case .Defaults:
            im.TextUnformatted("Defaults")
        case .Loaded:
            im.TextUnformatted("Loaded")
        case .Saved:
            im.TextUnformatted("Saved")
        case .Save_Failed:
            im.TextUnformatted("Save failed")
        }
        im.TextUnformatted(TWEAK_FILE_PATH)
        if im.BeginTabBar("Adriatic subjects") {
            if im.BeginTabItem("Terrain") {
                tweak_draw_terrain(editor)
                im.EndTabItem()
            }
            if im.BeginTabItem("Atmosphere") {
                tweak_draw_atmosphere(editor)
                im.EndTabItem()
            }
            if im.BeginTabItem("Player") {
                tweak_draw_player(editor)
                im.EndTabItem()
            }
            if im.BeginTabItem("Camera") {
                tweak_draw_camera(editor)
                im.EndTabItem()
            }
            if im.BeginTabItem("World") {
                tweak_draw_world(editor)
                im.EndTabItem()
            }
            if im.BeginTabItem("Particles") {
                tweak_draw_particles(editor)
                im.EndTabItem()
            }
            if im.BeginTabItem("Car") {
                tweak_draw_car(editor)
                im.EndTabItem()
            }
            if im.BeginTabItem("Postale") {
                tweak_draw_postale(editor)
                im.EndTabItem()
            }
            if im.BeginTabItem("Presentation") {
                tweak_draw_presentation(editor)
                im.EndTabItem()
            }
            im.EndTabBar()
        }
    }
    im.End()
    tweak_apply_to_editor(editor)
}
