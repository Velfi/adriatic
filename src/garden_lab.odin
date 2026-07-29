package main

import atmosphere "../packages/atmosphere"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import rl "zelda_engine:canvas2d"

Garden_Style :: enum u8 {
    Courtyard,
    Kitchen,
    Wild,
}

Garden_Plant_Kind :: enum u8 {
    Cypress,
    Citrus,
    Shrub,
    Flower,
    Herb,
}

Garden_Plant :: struct {
    position: third_person.Vec3,
    kind:     Garden_Plant_Kind,
    scale:    f32,
    color:    rl.Color,
}

Garden_Plan :: struct {
    style:       Garden_Style,
    seed:        u32,
    plants:      [96]Garden_Plant,
    plant_count: int,
}

garden_lab_seed := u32(73)
garden_lab_style := Garden_Style.Courtyard
garden_lab_plan: Garden_Plan

GARDEN_SOIL := rl.Color{91, 66, 43, 255}
GARDEN_STONE := rl.Color{202, 192, 165, 255}
GARDEN_STONE_DARK := rl.Color{139, 133, 116, 255}
GARDEN_LEAF := rl.Color{61, 105, 55, 255}
GARDEN_LEAF_LIGHT := rl.Color{93, 135, 67, 255}
GARDEN_CYPRESS := rl.Color{38, 78, 52, 255}
GARDEN_TERRACOTTA := rl.Color{171, 83, 48, 255}

garden_hash :: proc(value: u32) -> u32 {
    result := value
    result = (result ~ (result >> 16)) * 0x7feb352d
    result = (result ~ (result >> 15)) * 0x846ca68b
    return result ~ (result >> 16)
}

garden_random01 :: proc(seed: u32, index: int, salt: u32 = 0) -> f32 {
    value := garden_hash(seed + u32(index) * 0x9e3779b9 + salt)
    return f32(value & 0xffff) / 65535
}

garden_style_name :: proc(style: Garden_Style) -> cstring {
    switch style {
    case .Courtyard:
        return "COURTYARD"
    case .Kitchen:
        return "KITCHEN"
    case .Wild:
        return "WILD"
    }
    return "COURTYARD"
}

garden_add_plant :: proc(plan: ^Garden_Plan, plant: Garden_Plant) {
    if plan == nil || plan.plant_count >= len(plan.plants) do return
    plan.plants[plan.plant_count] = plant
    plan.plant_count += 1
}

garden_generate :: proc(seed: u32, style: Garden_Style) -> Garden_Plan {
    plan := Garden_Plan {
        seed  = seed,
        style = style,
    }
    switch style {
    case .Courtyard:
        // Four clipped corners frame a bright, formal central court.
        for index in 0 ..< 4 {
            x := index % 2 == 0 ? f32(-7.4) : f32(7.4)
            z := index < 2 ? f32(-5.4) : f32(5.4)
            garden_add_plant(&plan, {{x, 0, z}, .Cypress, .88 + garden_random01(seed, index) * .18, GARDEN_CYPRESS})
        }
        for index in 0 ..< 28 {
            side := index % 4
            along := -5.8 + f32(index / 4) * 1.92
            position := third_person.Vec3{}
            if side < 2 {
                position = {along, 0, side == 0 ? f32(-3.15) : f32(3.15)}
            } else {
                position = {side == 2 ? f32(-5.8) : f32(5.8), 0, along}
            }
            garden_add_plant(&plan, {position, .Shrub, .72 + garden_random01(seed, index, 11) * .22, GARDEN_LEAF})
        }
        for index in 0 ..< 24 {
            angle := f32(index) / 24 * math.PI * 2
            radius := 2.15 + (garden_random01(seed, index, 23) - .5) * .32
            palette := [3]rl.Color{{201, 76, 68, 255}, {237, 188, 71, 255}, {202, 116, 163, 255}}
            garden_add_plant(
                &plan,
                {
                    {math.cos(angle) * radius, 0, math.sin(angle) * radius},
                    .Flower,
                    .75 + garden_random01(seed, index, 29) * .35,
                    palette[index % len(palette)],
                },
            )
        }
    case .Kitchen:
        for index in 0 ..< 32 {
            bed := index / 8
            slot := index % 8
            x := -6.2 + f32(slot) * 1.75
            z := -4.5 + f32(bed) * 3
            color := bed % 2 == 0 ? GARDEN_LEAF_LIGHT : rl.Color{82, 119, 64, 255}
            garden_add_plant(&plan, {{x, 0, z}, .Herb, .7 + garden_random01(seed, index) * .45, color})
        }
        for index in 0 ..< 4 {
            garden_add_plant(
                &plan,
                {{-7.4 + f32(index) * 4.9, 0, 6.1}, .Citrus, .9 + garden_random01(seed, index, 51) * .2, GARDEN_LEAF},
            )
        }
    case .Wild:
        for index in 0 ..< 72 {
            x := -8.5 + garden_random01(seed, index, 61) * 17
            z := -6.5 + garden_random01(seed, index, 67) * 13
            // Preserve a loose S-shaped walking route through the meadow.
            path_x := math.sin(z * .34) * 1.5
            if abs(x - path_x) < 1.15 do continue
            palette := [4]rl.Color {
                {220, 178, 61, 255},
                {188, 82, 105, 255},
                {224, 220, 184, 255},
                {112, 130, 185, 255},
            }
            kind := garden_random01(seed, index, 71) > .82 ? Garden_Plant_Kind.Shrub : Garden_Plant_Kind.Flower
            garden_add_plant(
                &plan,
                {{x, 0, z}, kind, .65 + garden_random01(seed, index, 79) * .75, palette[index % len(palette)]},
            )
        }
    }
    return plan
}

garden_lab_rebuild :: proc() {
    garden_lab_plan = garden_generate(garden_lab_seed, garden_lab_style)
}

garden_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    garden_lab_seed = 73
    garden_lab_style = .Courtyard
    switch target {
    case "kitchen":
        garden_lab_style = .Kitchen
    case "wild", "meadow":
        garden_lab_style = .Wild
    case "alternate":
        garden_lab_seed = 211
    }
    garden_lab_rebuild()
    editor.in_map = true
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -20
    atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 35)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    editor.camera_pose = third_person.camera_look_at({11.4, 6.6, 12.8}, {0, .8, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

garden_lab_process_input :: proc(_: ^Editor) {
    changed := false
    if rl.IsKeyPressed(.R) {
        garden_lab_seed += 1
        changed = true
    }
    if rl.IsKeyPressed(.ONE) {
        garden_lab_style = .Courtyard
        changed = true
    }
    if rl.IsKeyPressed(.TWO) {
        garden_lab_style = .Kitchen
        changed = true
    }
    if rl.IsKeyPressed(.THREE) {
        garden_lab_style = .Wild
        changed = true
    }
    if changed do garden_lab_rebuild()
}

garden_draw_path_tile :: proc(x, z, width, depth: f32) {
    world_box({x, .035, z}, {width, .07, depth}, GARDEN_STONE)
}

garden_draw_flower :: proc(plant: Garden_Plant) {
    height := .52 * plant.scale
    world_vertical_prism({plant.position.x, height * .5, plant.position.z}, .045, .045, height, 0, GARDEN_LEAF)
    bloom := third_person.Vec3{plant.position.x, height + .08, plant.position.z}
    for petal in 0 ..< 5 {
        angle := f32(petal) * math.PI * 2 / 5
        world_vertical_prism(
            {bloom.x + math.cos(angle) * .10 * plant.scale, bloom.y, bloom.z + math.sin(angle) * .10 * plant.scale},
            .14 * plant.scale,
            .09 * plant.scale,
            .07,
            angle,
            plant.color,
        )
    }
    world_vertical_prism(bloom, .10 * plant.scale, .10 * plant.scale, .10, 0, {226, 171, 52, 255})
}

garden_draw_plant :: proc(plant: Garden_Plant) {
    switch plant.kind {
    case .Cypress:
        world_vertical_prism(
            {plant.position.x, 1.65 * plant.scale, plant.position.z},
            1.05 * plant.scale,
            .82 * plant.scale,
            3.3 * plant.scale,
            math.PI / 8,
            plant.color,
        )
        world_vertical_prism(
            {plant.position.x, 3.45 * plant.scale, plant.position.z},
            .56 * plant.scale,
            .48 * plant.scale,
            1.0 * plant.scale,
            0,
            plant.color,
        )
    case .Citrus:
        world_vertical_prism({plant.position.x, .8, plant.position.z}, .18, .18, 1.6, 0, {112, 75, 43, 255})
        world_vertical_prism(
            {plant.position.x, 1.85, plant.position.z},
            1.65 * plant.scale,
            1.45 * plant.scale,
            1.55 * plant.scale,
            math.PI / 8,
            plant.color,
        )
        for fruit in 0 ..< 5 {
            angle := f32(fruit) * 2.4
            world_vertical_prism(
                {
                    plant.position.x + math.cos(angle) * .58,
                    1.7 + f32(fruit % 2) * .4,
                    plant.position.z + math.sin(angle) * .58,
                },
                .16,
                .16,
                .16,
                angle,
                {222, 151, 44, 255},
            )
        }
    case .Shrub:
        world_vertical_prism(
            {plant.position.x, .42 * plant.scale, plant.position.z},
            .82 * plant.scale,
            .72 * plant.scale,
            .84 * plant.scale,
            math.PI / 8,
            plant.color,
        )
    case .Flower:
        garden_draw_flower(plant)
    case .Herb:
        for leaf in 0 ..< 5 {
            angle := f32(leaf) * math.PI * 2 / 5
            world_vertical_prism(
                {plant.position.x + math.cos(angle) * .16, .25, plant.position.z + math.sin(angle) * .16},
                .22 * plant.scale,
                .13 * plant.scale,
                .5 * plant.scale,
                angle,
                plant.color,
            )
        }
    }
}

world_garden_lab :: proc(_: ^Editor) {
    world_box({0, -.22, 0}, {21, .42, 16}, {113, 133, 82, 255})
    // Low dry-stone enclosure and a framed entrance.
    world_box({0, .42, -8}, {21.4, .84, .42}, GARDEN_STONE_DARK)
    world_box({-10.5, .42, 0}, {.42, .84, 16.4}, GARDEN_STONE_DARK)
    world_box({10.5, .42, 0}, {.42, .84, 16.4}, GARDEN_STONE_DARK)
    world_box({-6.2, .42, 8}, {8.2, .84, .42}, GARDEN_STONE_DARK)
    world_box({6.2, .42, 8}, {8.2, .84, .42}, GARDEN_STONE_DARK)

    switch garden_lab_style {
    case .Courtyard:
        for x in -4 ..= 4 do garden_draw_path_tile(f32(x) * 1.35, 0, 1.22, 1.1)
        for z in -3 ..= 3 do garden_draw_path_tile(0, f32(z) * 1.35, 1.1, 1.22)
        world_vertical_prism({0, .30, 0}, 2.35, 2.35, .60, math.PI / 8, GARDEN_STONE)
        world_vertical_prism({0, .66, 0}, 1.7, 1.7, .18, math.PI / 8, {84, 139, 151, 255})
        world_vertical_prism({0, 1.05, 0}, .25, .25, .85, 0, GARDEN_STONE_DARK)
        world_vertical_prism({0, 1.54, 0}, .66, .66, .16, math.PI / 8, {129, 185, 195, 255})
    case .Kitchen:
        for bed in 0 ..< 4 {
            z := -4.5 + f32(bed) * 3
            world_box({0, .13, z}, {14.6, .26, 1.55}, GARDEN_SOIL)
            world_box({0, .08, z - .86}, {15.1, .16, .14}, GARDEN_TERRACOTTA)
            world_box({0, .08, z + .86}, {15.1, .16, .14}, GARDEN_TERRACOTTA)
        }
        for z in -5 ..= 5 do garden_draw_path_tile(0, f32(z) * 1.35, 1.15, 1.22)
    case .Wild:
        for z in -5 ..= 5 {
            fz := f32(z) * 1.35
            garden_draw_path_tile(math.sin(fz * .34) * 1.5, fz, 1.7, 1.25)
        }
    }
    for plant_index in 0 ..< garden_lab_plan.plant_count {
        garden_draw_plant(garden_lab_plan.plants[plant_index])
    }
}

garden_lab_draw_ui :: proc(_: ^Editor, width, _: i32) {
    panel := rl.Rectangle{24, 24, 410, 100}
    rl.DrawRectangleRounded(panel, .16, 8, {19, 31, 27, 226})
    rl.DrawRectangleRoundedLinesEx(panel, .16, 8, 1, {111, 146, 111, 255})
    rl.DrawTextEx(rl.Font{}, "GARDEN GENERATOR", {38, 38}, 18, 1, {232, 224, 189, 255})
    summary := fmt.ctprintf(
        "%s  /  SEED %d  /  %d PLANTS",
        garden_style_name(garden_lab_style),
        garden_lab_seed,
        garden_lab_plan.plant_count,
    )
    rl.DrawTextEx(rl.Font{}, summary, {38, 65}, 13, 1, {174, 207, 160, 255})
    rl.DrawTextEx(rl.Font{}, "1 COURTYARD   2 KITCHEN   3 WILD   R REGENERATE", {38, 91}, 11, 1, {184, 191, 174, 255})
    _ = width
}
