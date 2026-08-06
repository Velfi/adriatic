package main

import atmosphere "../packages/atmosphere"
import estuaries "../packages/estuaries"
import spring_river "../packages/spring_river"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:math"
import "core:strconv"
import canvas2d "zelda_engine:canvas2d"

SPRING_RIVER_LAB_DEFAULT_SEED :: u32(0x53505247)
SPRING_RIVER_LAB_ESTUARY_HALF_WIDTH :: f32(170)
SPRING_RIVER_LAB_ESTUARY_HALF_LENGTH :: f32(190)

spring_river_lab_seed := SPRING_RIVER_LAB_DEFAULT_SEED
spring_river_lab_discharge := f32(.72)
spring_river_lab_meander := f32(.62)
spring_river_lab_gradient := f32(.052)
spring_river_lab_plan: spring_river.Plan
spring_river_lab_estuary: estuaries.Plan

spring_river_lab_estuary_coordinates :: proc(x, z: f32) -> (nx, nz: f32) {
    mouth := spring_river.mouth(&spring_river_lab_plan)
    side := spring_river.Vec2{-mouth.direction[1], mouth.direction[0]}
    relative := spring_river.Vec2{x, z} - mouth.position
    along := relative[0] * mouth.direction[0] + relative[1] * mouth.direction[1]
    lateral := relative[0] * side[0] + relative[1] * side[1]
    return lateral / SPRING_RIVER_LAB_ESTUARY_HALF_WIDTH, 1 - along / SPRING_RIVER_LAB_ESTUARY_HALF_LENGTH
}

spring_river_lab_smooth01 :: #force_inline proc(value: f32) -> f32 {
    t := clamp(value, f32(0), f32(1))
    return t * t * (3 - 2 * t)
}

spring_river_lab_base_height :: #force_inline proc(x, z: f32) -> f32 {
    downstream := clamp((z + 105) / f32(230), f32(0), f32(1))
    valley := min(f32(5), abs(x) * .018) * spring_river_lab_smooth01(abs(x) / 105)
    undulation := math.sin(x * .031 + z * .012) * .34 + math.sin(z * .045) * .18
    return 18.8 - downstream * 12.7 + valley + undulation
}

spring_river_lab_terrain_sample :: proc(_: ^Editor, world_x, world_z: f32) -> Lab_Terrain_Sample {
    base := spring_river_lab_base_height(world_x, world_z)
    nx, nz := spring_river_lab_estuary_coordinates(world_x, world_z)
    if math.abs(nx) <= 1 && nz >= -1 && nz <= 1 {
        base = estuaries.sample_elevation(&spring_river_lab_estuary, nx, nz)
    }
    river := spring_river.sample(&spring_river_lab_plan, {world_x, world_z})
    carved := base
    if river.bank_influence > 0 {
        bank_target := river.water_level + .20 + (1 - river.bank_influence) * 1.25
        carved = min(base, base + (bank_target - base) * river.bank_influence)
        if river.inside_water do carved = min(carved, river.bed_height)
    }
    return {height = carved, material = -river.wetness * 1.4 + (1 - river.bank_influence) * .18}
}

spring_river_lab_regenerate :: proc(editor: ^Editor) {
    estuaries.destroy(&spring_river_lab_estuary)
    spring_river_lab_plan = spring_river.generate(
        {
            seed = spring_river_lab_seed,
            source = {-16, -105},
            direction = {.10, 1},
            source_height = 14.5,
            length = 230,
            segment_length = 2,
            gradient = spring_river_lab_gradient,
            discharge = spring_river_lab_discharge,
            meander = spring_river_lab_meander,
            spring_radius = 4.8,
        },
    )
    mouth := spring_river.mouth(&spring_river_lab_plan)
    estuary_config := estuaries.config_from_river_mouth(
        mouth,
        spring_river_lab_discharge >= .9 ? .Distributary_Delta : .Tidal_Estuary,
        SPRING_RIVER_LAB_ESTUARY_HALF_WIDTH,
    )
    estuary_config.seed = spring_river.hash(spring_river_lab_seed ~ 0x45535455)
    spring_river_lab_estuary = estuaries.generate(estuary_config)
    if editor == nil do return
    _ = lab_terrain_load(
        editor,
        {
            half_extent_x = 210,
            half_extent_z = 150,
            sea_level = spring_river_lab_estuary.config.mean_sea_level,
            outside_height = 12,
            outside_material = .18,
        },
        spring_river_lab_terrain_sample,
    )
}

spring_river_lab_exit :: proc(_: ^Editor) {
    estuaries.destroy(&spring_river_lab_estuary)
}

spring_river_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    spring_river_lab_seed = SPRING_RIVER_LAB_DEFAULT_SEED
    spring_river_lab_discharge = .72
    spring_river_lab_meander = .62
    spring_river_lab_gradient = .052
    switch target {
    case "", "spring":
    case "brook":
        spring_river_lab_discharge = .34
        spring_river_lab_meander = .78
    case "river":
        spring_river_lab_discharge = 1.2
        spring_river_lab_meander = .45
        spring_river_lab_gradient = .035
    case:
        if parsed, ok := strconv.parse_u64(target, 0); ok {
            spring_river_lab_seed = u32(parsed)
        } else {
            return false
        }
    }
    spring_river_lab_regenerate(editor)
    editor.in_map = false
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 35)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    editor.camera_pose = third_person.camera_look_at({126, 72, -138}, {-2, 10, 6})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    set_pointer_locked(false)
    return true
}

spring_river_lab_process_input :: proc(editor: ^Editor) {
    changed := false
    if canvas2d.IsKeyPressed(.LEFT) do spring_river_lab_seed, changed = spring_river_lab_seed - 1, true
    if canvas2d.IsKeyPressed(.RIGHT) do spring_river_lab_seed, changed = spring_river_lab_seed + 1, true
    if canvas2d.IsKeyPressed(.R) do spring_river_lab_seed, changed = spring_river.hash(spring_river_lab_seed + 0x9e3779b9), true
    if canvas2d.IsKeyPressed(.A) do spring_river_lab_meander, changed = max(f32(0), spring_river_lab_meander - .1), true
    if canvas2d.IsKeyPressed(.D) do spring_river_lab_meander, changed = min(f32(1), spring_river_lab_meander + .1), true
    if canvas2d.IsKeyPressed(.DOWN) do spring_river_lab_discharge, changed = max(f32(.1), spring_river_lab_discharge - .1), true
    if canvas2d.IsKeyPressed(.UP) do spring_river_lab_discharge, changed = min(f32(1.8), spring_river_lab_discharge + .1), true
    if changed do spring_river_lab_regenerate(editor)
}

world_spring_river_lab :: proc(_: ^Editor) {
    water := canvas2d.Color{47, 126, 153, 218}
    foam := canvas2d.Color{157, 211, 214, 205}
    for index in 0 ..< spring_river_lab_plan.point_count - 1 {
        a, b := spring_river_lab_plan.points[index], spring_river_lab_plan.points[index + 1]
        delta := b.position - a.position
        length := f32(math.sqrt(f64(delta[0] * delta[0] + delta[1] * delta[1])))
        yaw := math.atan2(-delta[0], delta[1])
        center := third_person.Vec3 {
            (a.position[0] + b.position[0]) * .5,
            (a.water_level + b.water_level) * .5 + .025,
            (a.position[1] + b.position[1]) * .5,
        }
        width := (a.width + b.width) * .5 * .90
        world_box_rotated(center, {width, .05, length + .18}, yaw, water)
        if (index % 7) == 4 {
            world_box_rotated({center.x, center.y + .035, center.z}, {width * .62, .025, .18}, yaw, foam)
        }
    }
    source := spring_river_lab_plan.points[0]
    stone := canvas2d.Color{110, 116, 99, 255}
    for index in 0 ..< 9 {
        angle := f32(index) / 9 * math.PI * 2
        radius := spring_river_lab_plan.config.spring_radius * (.72 + f32(index & 1) * .14)
        x := source.position[0] + math.cos(angle) * radius
        z := source.position[1] + math.sin(angle) * radius
        world_box_rotated({x, source.water_level + .18, z}, {.8, .55, 1.05}, angle * .7, stone)
    }
}

spring_river_lab_draw_ui :: proc(_: ^Editor, _: i32, _: i32) {
    panel := canvas2d.Rectangle{24, 24, 625, 174}
    canvas2d.DrawRectangleRounded(panel, .10, 8, {15, 31, 31, 232})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {91, 157, 153, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "SPRING & RIVER GENERATOR LAB", {40, 40}, 19, 1, {226, 239, 208, 255})
    status := fmt.ctprintf(
        "SEED %08X   %d REACHES   FLOW %.0f%%   MEANDER %.0f%%   DROP %.1fm",
        spring_river_lab_seed,
        spring_river_lab_plan.point_count - 1,
        spring_river_lab_discharge * 100,
        spring_river_lab_meander * 100,
        spring_river_lab_plan.total_drop,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, status, {40, 73}, 12, 1, {184, 220, 210, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf(
            "%s   %d OUTLETS   SEDIMENT %.0f%%",
            estuaries.archetype_name(spring_river_lab_estuary.config.archetype),
            spring_river_lab_estuary.diagnostics.outlet_count,
            spring_river_lab_estuary.config.sediment_load * 100,
        ),
        {40, 98},
        11,
        1,
        {166, 196, 183, 255},
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "LEFT/RIGHT SEED   R REROLL   A/D MEANDER   UP/DOWN FLOW",
        {40, 125},
        11,
        1,
        {166, 196, 183, 255},
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "SPRING  >  RIVER  >  TIDAL ESTUARY / DISTRIBUTARY DELTA",
        {40, 153},
        10,
        1,
        {137, 177, 157, 255},
    )
}
