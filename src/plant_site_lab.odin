package main

import atmosphere "../packages/atmosphere"
import plants "../packages/plants"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

PLANT_SITE_LAB_HALF_EXTENT :: f32(120)
PLANT_SITE_LAB_MIN_DISTANCE :: f32(9)
PLANT_SITE_LAB_SAMPLE_CAPACITY :: 520

Plant_Site_Lab_Sample :: struct {x, z: f32}

plant_site_lab_samples: [PLANT_SITE_LAB_SAMPLE_CAPACITY]Plant_Site_Lab_Sample
plant_site_lab_sample_count: int
plant_site_lab_seed := u32(0x53495445)
plant_site_lab_species := plants.Species.Olive
plant_site_lab_species_dropdown_open := false

plant_site_lab_species_dropdown_bounds :: proc() -> canvas2d.Rectangle {
    return {40, 72, 250, 28}
}

plant_site_lab_resample_bounds :: proc() -> canvas2d.Rectangle {
    return {304, 72, 146, 28}
}

plant_site_lab_species_option_bounds :: proc(index: int) -> canvas2d.Rectangle {
    column := index % 4
    row := index / 4
    return {24 + f32(column) * 198, 100 + f32(row) * 26, 198, 26}
}

plant_site_lab_hash :: #force_inline proc(value: u32) -> u32 {
    result := value
    result = (result ~ (result >> 16)) * 0x7feb352d
    result = (result ~ (result >> 15)) * 0x846ca68b
    return result ~ (result >> 16)
}

plant_site_lab_random01 :: #force_inline proc(value: u32) -> f32 {
    return f32(plant_site_lab_hash(value) & 0xffff) / 65535
}

plant_site_lab_smoothstep :: #force_inline proc(edge_0, edge_1, value: f32) -> f32 {
    t := clamp((value - edge_0) / max(edge_1 - edge_0, f32(.0001)), 0, 1)
    return t * t * (3 - 2 * t)
}

plant_site_lab_terrain_sample :: proc(_: ^Editor, world_x, world_z: f32) -> Lab_Terrain_Sample {
    u := clamp((world_x + PLANT_SITE_LAB_HALF_EXTENT) / (PLANT_SITE_LAB_HALF_EXTENT * 2), 0, 1)
    v := clamp((world_z + PLANT_SITE_LAB_HALF_EXTENT) / (PLANT_SITE_LAB_HALF_EXTENT * 2), 0, 1)
    inland := (u + v) * .5
    shore := plant_site_lab_smoothstep(.13, .27, inland)
    mountain_dx := world_x - 88
    mountain_dz := world_z - 88
    mountain_distance := f32(math.sqrt(f64(mountain_dx * mountain_dx + mountain_dz * mountain_dz)))
    mountain := 1 - plant_site_lab_smoothstep(22, 168, mountain_distance)
    mountain *= mountain
    undulation := f32(math.sin(f64(world_x * .071))) * 1.4 + f32(math.sin(f64(world_z * .057 + world_x * .019))) * 1.1
    height := -7 + shore * (8 + inland * 8 + mountain * 74 + undulation)
    material := f32(-.92)
    if shore > .24 do material = .08
    if height > 18 do material = .58
    if height > 42 do material = .86
    return {height = height, material = material}
}

plant_site_lab_regenerate_samples :: proc() {
    plant_site_lab_sample_count = 0
    minimum_distance_squared := PLANT_SITE_LAB_MIN_DISTANCE * PLANT_SITE_LAB_MIN_DISTANCE
    // Fixed-budget dart throwing gives deterministic Poisson-disc coverage.
    for attempt in 0 ..< 32000 {
        if plant_site_lab_sample_count >= PLANT_SITE_LAB_SAMPLE_CAPACITY do break
        x := -PLANT_SITE_LAB_HALF_EXTENT + plant_site_lab_random01(plant_site_lab_seed + u32(attempt) * 2) * PLANT_SITE_LAB_HALF_EXTENT * 2
        z := -PLANT_SITE_LAB_HALF_EXTENT + plant_site_lab_random01(plant_site_lab_seed + u32(attempt) * 2 + 1) * PLANT_SITE_LAB_HALF_EXTENT * 2
        accepted := true
        for sample in plant_site_lab_samples[:plant_site_lab_sample_count] {
            dx, dz := x - sample.x, z - sample.z
            if dx * dx + dz * dz < minimum_distance_squared {
                accepted = false
                break
            }
        }
        if !accepted do continue
        plant_site_lab_samples[plant_site_lab_sample_count] = {x, z}
        plant_site_lab_sample_count += 1
    }
}

plant_site_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    species_index := plant_generator_find_species(target)
    if target != "" && species_index < 0 do return false
    if species_index >= 0 do plant_site_lab_species = plants.Species(species_index)
    plant_site_lab_species_dropdown_open = false
    plant_site_lab_regenerate_samples()
    if !lab_terrain_load(
        editor,
        {
            half_extent_x = PLANT_SITE_LAB_HALF_EXTENT,
            half_extent_z = PLANT_SITE_LAB_HALF_EXTENT,
            sea_level = 0,
            outside_height = -7,
            outside_material = -.92,
        },
        plant_site_lab_terrain_sample,
    ) {
        return false
    }
    atmosphere.set_world_minutes(&editor.atmosphere, 14 * 60)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    camera := third_person.default_camera()
    camera.yaw_radians = math.PI * 1.25
    camera.pitch_radians = .42
    camera.distance = 330
    lab_scene_configure_camera(editor, {8, 19, 8}, camera)
    return true
}

plant_site_lab_world :: proc(editor: ^Editor) {
    if editor == nil do return
    profile := plants.garden_profile(plant_site_lab_species)
    scale := clamp(3.2 / max(profile.mature_height, f32(.25)), f32(.45), f32(2.2))
    shared_seed := u64(plant_site_lab_seed) << 32 | u64(0x504c414e)
    for sample in plant_site_lab_samples[:plant_site_lab_sample_count] {
        ground := terrain.sample_surface_height(&editor.project, 0, sample.x, sample.z)
        if ground <= editor.project.sea_level + .18 do continue
        base := third_person.Vec3{sample.x, ground, sample.z}
        site := generated_plant_site_context(editor, base)
        _ = world_generated_plant(
            plant_site_lab_species,
            shared_seed,
            base,
            scale,
            0,
            .Free_Standing,
            nil,
            .Far,
            0,
            .92,
            false,
            site,
        )
    }
}

plant_site_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    species_index := int(plant_site_lab_species)
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        mouse := canvas2d.GetMousePosition()
        if canvas2d.CheckCollisionPointRec(mouse, plant_site_lab_species_dropdown_bounds()) {
            plant_site_lab_species_dropdown_open = !plant_site_lab_species_dropdown_open
        } else if plant_site_lab_species_dropdown_open {
            selected := false
            for index in 0 ..< plants.SPECIES_COUNT {
                if canvas2d.CheckCollisionPointRec(mouse, plant_site_lab_species_option_bounds(index)) {
                    species_index = index
                    plant_site_lab_species_dropdown_open = false
                    selected = true
                    break
                }
            }
            if !selected do plant_site_lab_species_dropdown_open = false
        } else if canvas2d.CheckCollisionPointRec(mouse, plant_site_lab_resample_bounds()) {
            plant_site_lab_seed = plant_site_lab_hash(plant_site_lab_seed + 0x9e3779b9)
            plant_site_lab_regenerate_samples()
        }
    }
    if canvas2d.IsKeyPressed(.LEFT) do species_index = (species_index + plants.SPECIES_COUNT - 1) % plants.SPECIES_COUNT
    if canvas2d.IsKeyPressed(.RIGHT) do species_index = (species_index + 1) % plants.SPECIES_COUNT
    if canvas2d.IsKeyPressed(.R) {
        plant_site_lab_seed = plant_site_lab_hash(plant_site_lab_seed + 0x9e3779b9)
        plant_site_lab_regenerate_samples()
    }
    plant_site_lab_species = plants.Species(species_index)
}

plant_site_lab_draw_ui :: proc(_: ^Editor, _: i32, _: i32) {
    panel := canvas2d.Rectangle{24, 24, 590, 130}
    canvas2d.DrawRectangleRounded(panel, .10, 8, {10, 27, 34, 232})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {99, 163, 158, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "PLANT SITE CONDITIONS", {40, 40}, 19, 1, {239, 224, 179, 255})
    dropdown := plant_site_lab_species_dropdown_bounds()
    resample := plant_site_lab_resample_bounds()
    mouse := canvas2d.GetMousePosition()
    canvas2d.DrawTextEx(canvas2d.Font{}, "SPECIES", {dropdown.x, 59}, 10, 1, {190, 207, 211, 255})
    control_bounds := [2]canvas2d.Rectangle{dropdown, resample}
    for bounds in control_bounds {
        hovered := canvas2d.CheckCollisionPointRec(mouse, bounds)
        canvas2d.DrawRectangleRounded(bounds, .16, 6, hovered ? canvas2d.Color{45, 70, 70, 255} : canvas2d.Color{25, 49, 52, 248})
        canvas2d.DrawRectangleRoundedLinesEx(bounds, .16, 6, 1, {99, 163, 158, 255})
    }
    canvas2d.DrawTextEx(canvas2d.Font{}, fmt.ctprintf("%s", plants.species_name(plant_site_lab_species)), {dropdown.x + 10, dropdown.y + 7}, 12, 1, {239, 224, 179, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, plant_site_lab_species_dropdown_open ? "^" : "v", {dropdown.x + dropdown.width - 18, dropdown.y + 7}, 12, 1, {177, 221, 213, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "RESAMPLE", {resample.x + 12, resample.y + 7}, 12, 1, {239, 224, 179, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, fmt.ctprintf("%d SAMPLES", plant_site_lab_sample_count), {40, 113}, 11, 1, {177, 221, 213, 255})
    if plant_site_lab_species_dropdown_open {
        for index in 0 ..< plants.SPECIES_COUNT {
            bounds := plant_site_lab_species_option_bounds(index)
            hovered := canvas2d.CheckCollisionPointRec(mouse, bounds)
            selected := index == int(plant_site_lab_species)
            fill := (hovered || selected) ? canvas2d.Color{45, 70, 70, 255} : canvas2d.Color{15, 37, 40, 250}
            canvas2d.DrawRectangleRec(bounds, fill)
            canvas2d.DrawRectangleRoundedLinesEx(bounds, 0, 1, 1, {79, 133, 131, 255})
            canvas2d.DrawTextEx(canvas2d.Font{}, fmt.ctprintf("%s", plants.species_name(plants.Species(index))), {bounds.x + 9, bounds.y + 6}, 11, 1, selected ? canvas2d.Color{239, 224, 179, 255} : canvas2d.Color{190, 215, 211, 255})
        }
    }
}
