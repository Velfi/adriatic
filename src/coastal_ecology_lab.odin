package main

import atmosphere "../packages/atmosphere"
import rocky "../packages/coastal_ecology"
import "core:fmt"
import "core:math"
import "core:strconv"
import canvas "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

ROCKY_BEACH_DEFAULT_SEED :: u32(0x54494445)

rocky_beach_plan: rocky.Plan
rocky_beach_config: rocky.Config
rocky_beach_tide_phase := f32(.12)
rocky_beach_tide_running := true

Rocky_Beach_Lab_View :: enum u8 {
    Coast,
    Marine_Overview,
    Seagrass,
    Macroalgae,
    Coralligenous,
}

rocky_beach_lab_view := Rocky_Beach_Lab_View.Coast

rocky_beach_lab_terrain_sample :: proc(_: ^Editor, world_x, world_z: f32) -> Lab_Terrain_Sample {
    cell := rocky.sample(&rocky_beach_plan, world_x, world_z)
    material: f32
    switch cell.habitat {
    case .Subtidal:
        material = -.72
    case .Reef:
        material = -.32
    case .Rock_Platform:
        material = -.20 - cell.algae * .22
    case .Tidepool:
        material = -.48
    case .Pocket_Beach:
        material = -.94
    case .Wrack_Shore:
        material = -.68
    case .Backshore:
        material = -.08
    case .Coastal_Scrub:
        material = .58
    }
    return {height = cell.height, material = material}
}

rocky_beach_regenerate :: proc(editor: ^Editor) {
    rocky_beach_plan = rocky.generate(rocky_beach_config)
    if editor == nil do return
    _ = lab_terrain_load(editor, {
            half_extent_x    = rocky_beach_config.width * .5,
            half_extent_z    = rocky_beach_config.depth * .5,
            sea_level        = rocky.tide_height(rocky_beach_config, rocky_beach_tide_phase),
            outside_height   = 5.5,
            outside_material = -.08,
        }, rocky_beach_lab_terrain_sample)
}

rocky_beach_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    rocky_beach_config = rocky.default_config()
    rocky_beach_config.seed = ROCKY_BEACH_DEFAULT_SEED
    rocky_beach_tide_phase = .035
    rocky_beach_tide_running = true
    rocky_beach_lab_view = .Coast
    switch target {
    case "marine", "marine-overview", "overview":
        rocky_beach_lab_view = .Marine_Overview
    case "seagrass", "posidonia":
        rocky_beach_lab_view = .Seagrass
    case "macroalgae", "algae":
        rocky_beach_lab_view = .Macroalgae
    case "coralligenous", "gorgonian":
        rocky_beach_lab_view = .Coralligenous
    case:
    }
    if target != "" && rocky_beach_lab_view == .Coast {
        if parsed, ok := strconv.parse_u64(target, 0); ok do rocky_beach_config.seed = u32(parsed)
    }
    rocky_beach_regenerate(editor)
    editor.postale_visible, editor.libellula_visible, editor.rondine_visible = false, false, false
    editor.in_map = false
    editor.capture_world_only = false
    atmosphere.set_world_minutes(&editor.atmosphere, 10 * 60 + 20)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    if rocky_beach_lab_view == .Coast {
        editor.camera_pose = third_person.camera_look_at({108, 72, -102}, {0, 1.5, 4})
    } else {
        // A low oblique view keeps roots visible through the water while still
        // showing enough seabed to judge density and transitions.
        editor.camera_pose = third_person.camera_look_at({43, 18, -42}, {0, -2.0, 7})
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    set_pointer_locked(false)
    return true
}

rocky_beach_lab_process_input :: proc(editor: ^Editor) {
    changed := false
    if canvas.IsKeyPressed(.LEFT) do rocky_beach_config.seed, changed = rocky_beach_config.seed - 1, true
    if canvas.IsKeyPressed(.RIGHT) do rocky_beach_config.seed, changed = rocky_beach_config.seed + 1, true
    if canvas.IsKeyPressed(.R) do rocky_beach_config.seed, changed = rocky.hash(rocky_beach_config.seed + 0x9e3779b9), true
    if canvas.IsKeyPressed(.SPACE) do rocky_beach_tide_running = !rocky_beach_tide_running
    if canvas.IsKeyPressed(.Q) do rocky_beach_tide_phase = max(f32(0), rocky_beach_tide_phase - .025)
    if canvas.IsKeyPressed(.E) do rocky_beach_tide_phase = min(f32(1), rocky_beach_tide_phase + .025)
    if canvas.IsKeyPressed(.DOWN) {
        rocky_beach_config.tide_range = max(f32(.8), rocky_beach_config.tide_range - .25)
        changed = true
    }
    if canvas.IsKeyPressed(.UP) {
        rocky_beach_config.tide_range = min(f32(7), rocky_beach_config.tide_range + .25)
        changed = true
    }
    if canvas.IsKeyPressed(.B) {
        rocky_beach_config.biology = rocky_beach_config.biology > .45 ? f32(.28) : f32(.88)
        changed = true
    }
    if canvas.IsKeyPressed(.ONE) {
        rocky_beach_config.headlands, rocky_beach_config.embayments, rocky_beach_config.platforms = .92, .42, .88
        rocky_beach_config.relief = 17
        changed = true
    }
    if canvas.IsKeyPressed(.TWO) {
        rocky_beach_config.headlands, rocky_beach_config.embayments, rocky_beach_config.platforms = .54, .96, .48
        rocky_beach_config.relief = 12
        changed = true
    }
    if canvas.IsKeyPressed(.THREE) {
        rocky_beach_config.headlands, rocky_beach_config.embayments, rocky_beach_config.platforms = .28, .72, .78
        rocky_beach_config.relief = 7
        changed = true
    }
    if changed do rocky_beach_regenerate(editor)
    if rocky_beach_tide_running {
        // Input is processed once per rendered frame. A deliberately slow,
        // fixed laboratory clock also keeps capture sequences deterministic.
        rocky_beach_tide_phase += f32(.00042)
        if rocky_beach_tide_phase >= 1 do rocky_beach_tide_phase -= 1
    }
    editor.project.sea_level = rocky.tide_height(rocky_beach_config, rocky_beach_tide_phase)
}

rocky_beach_species_color :: proc(species: rocky.Species, submerged: bool) -> canvas.Color {
    color: canvas.Color
    switch species {
    case .Barnacle:
        color = {246, 225, 176, 255}
    case .Mussel:
        color = {52, 52, 91, 255}
    case .Anemone:
        color = {248, 82, 111, 255}
    case .Limpet:
        color = {221, 174, 92, 255}
    case .Seaweed:
        color = {55, 159, 91, 255}
    case .Urchin:
        color = {104, 62, 146, 255}
    case .Starfish:
        color = {255, 137, 53, 255}
    }
    if submerged {
        color.r = u8(f32(color.r) * .72)
        color.g = u8(min(f32(255), f32(color.g) * .88 + 18))
        color.b = u8(min(f32(255), f32(color.b) * 1.08 + 14))
    }
    return color
}

rocky_beach_prism :: proc(center: third_person.Vec3, radius_x, radius_z, height, yaw: f32, color: canvas.Color) {
    SEGMENTS :: 8
    top_center := third_person.Vec3{center.x, center.y + height, center.z}
    for segment in 0 ..< SEGMENTS {
        angle_a := f32(segment) / SEGMENTS * math.PI * 2 + yaw
        angle_b := f32(segment + 1) / SEGMENTS * math.PI * 2 + yaw
        a := third_person.Vec3 {
            center.x + math.cos(angle_a) * radius_x,
            center.y,
            center.z + math.sin(angle_a) * radius_z,
        }
        b := third_person.Vec3 {
            center.x + math.cos(angle_b) * radius_x,
            center.y,
            center.z + math.sin(angle_b) * radius_z,
        }
        ta := third_person.Vec3 {
            center.x + math.cos(angle_a) * radius_x * .72,
            center.y + height * .72,
            center.z + math.sin(angle_a) * radius_z * .72,
        }
        tb := third_person.Vec3 {
            center.x + math.cos(angle_b) * radius_x * .72,
            center.y + height * .72,
            center.z + math.sin(angle_b) * radius_z * .72,
        }
        world_triangle(a, ta, b, color)
        world_triangle(b, ta, tb, color)
        world_triangle(ta, top_center, tb, color)
    }
}

rocky_beach_draw_organism :: proc(organism: rocky.Organism, submerged: bool) {
    color := rocky_beach_species_color(organism.species, submerged)
    // Exaggerated silhouettes make ecological zones readable from the lab's
    // authored camera without turning the scene into a scientific plot.
    s := organism.scale * 1.75
    center := third_person.Vec3{organism.x, organism.y + .10 * s, organism.z}
    switch organism.species {
    case .Barnacle:
        rocky_beach_prism(center, .16 * s, .16 * s, .24 * s, organism.yaw, color)
    case .Mussel:
        rocky_beach_prism(center, .14 * s, .28 * s, .18 * s, organism.yaw, color)
    case .Anemone:
        rocky_beach_prism(center, .26 * s, .26 * s, .30 * s, organism.yaw, color)
        crown := color
        crown.r = u8(min(f32(255), f32(crown.r) + 18))
        rocky_beach_prism(
            {center.x, center.y + .22 * s, center.z},
            .32 * s,
            .32 * s,
            .12 * s,
            organism.yaw + .2,
            crown,
        )
    case .Limpet:
        rocky_beach_prism(center, .25 * s, .22 * s, .20 * s, organism.yaw, color)
    case .Seaweed:
        for blade in 0 ..< 3 {
            offset := (f32(blade) - 1) * .13 * s
            lean :=
                submerged ? f32(math.sin(f64(rocky_beach_tide_phase * math.PI * 2 + organism.yaw + f32(blade)))) * .12 : f32(0)
            world_box_rotated(
                {center.x + offset + lean, center.y + .35 * s, center.z},
                {.08 * s, .78 * s, .12 * s},
                organism.yaw + lean,
                color,
            )
        }
    case .Urchin:
        rocky_beach_prism(center, .31 * s, .31 * s, .38 * s, organism.yaw, color)
        world_box_rotated(center, {.52 * s, .08 * s, .08 * s}, organism.yaw, color)
        world_box_rotated(center, {.08 * s, .08 * s, .52 * s}, organism.yaw, color)
    case .Starfish:
        for arm in 0 ..< 5 {
            angle := organism.yaw + f32(arm) / 5 * math.PI * 2
            x := center.x + f32(math.sin(f64(angle))) * .14 * s
            z := center.z + f32(math.cos(f64(angle))) * .14 * s
            world_box_rotated({x, center.y, z}, {.11 * s, .07 * s, .42 * s}, angle, color)
        }
    }
}

world_rocky_beach_lab :: proc(editor: ^Editor) {
    ocean := rocky.tide_height(rocky_beach_config, rocky_beach_tide_phase)
    presentation_x := rocky.GRID_X - 1
    presentation_z := rocky.GRID_Z - 1
    step_x := rocky_beach_config.width / f32(presentation_x)
    step_z := rocky_beach_config.depth / f32(presentation_z)
    water_alpha := rocky_beach_lab_view == .Coast ? u8(214) : u8(150)
    water := canvas.Color{42, 166, 190, water_alpha}
    up := third_person.Vec3{0, 1, 0}
    // A shared triangle surface replaces the old per-cell water blocks. The
    // simulation grid now drives an organic-looking sheet without being drawn.
    for z in 0 ..< presentation_z {
        for x in 0 ..< presentation_x {
            points: [4]third_person.Vec3
            levels: [4]f32
            visible := true
            level_min, level_max := f32(1e9), f32(-1e9)
            average_depth := f32(0)
            for corner in 0 ..< 4 {
                cx := x + (corner & 1)
                cz := z + (corner >> 1)
                world_x := f32(cx) * step_x - rocky_beach_config.width * .5
                world_z := f32(cz) * step_z - rocky_beach_config.depth * .5
                cell := rocky.sample(&rocky_beach_plan, world_x, world_z)
                level, wet := rocky.water_level(cell, rocky_beach_config, rocky_beach_tide_phase)
                if !wet || (ocean <= cell.height && cell.water_trap < .50) do visible = false
                levels[corner] = level
                level_min, level_max = min(level_min, level), max(level_max, level)
                average_depth += max(level - cell.height, f32(0)) * .25
                points[corner] = {world_x, level, world_z}
            }
            if level_max - level_min > .38 do visible = false
            if !visible do continue
            surface := (levels[0] + levels[1] + levels[2] + levels[3]) * .25 + .045
            ripple := f32(math.sin(f64(f32(x) * .72 + f32(z) * .49 + rocky_beach_tide_phase * 30))) * .018
            for &point in points do point.y = surface + ripple
            _ = average_depth
            color := water
            world_triangle_smooth_lit(points[0], points[2], points[1], up, up, up, color, color, color, .18)
            world_triangle_smooth_lit(points[1], points[2], points[3], up, up, up, color, color, color, .18)
        }
    }
    // Wrack is a compact generated instance list, not a dynamic particle
    // simulation. Layered strands make the high-water contour legible as a
    // continuous deposit while keeping draw work proportional to debris count.
    for strand, index in rocky_beach_plan.wrack[:rocky_beach_plan.wrack_count] {
        damp := canvas.Color{76, 91, 44, 255}
        dry := canvas.Color{147, 112, 56, 255}
        color := canvas.Color {
            u8(f32(damp.r) + (f32(dry.r) - f32(damp.r)) * strand.dry),
            u8(f32(damp.g) + (f32(dry.g) - f32(damp.g)) * strand.dry),
            u8(f32(damp.b) + (f32(dry.b) - f32(damp.b)) * strand.dry),
            255,
        }
        lift := .07 + f32(index % 3) * .018
        world_box_rotated(
            {strand.x, strand.y + lift, strand.z},
            {strand.width, .055, strand.length},
            strand.yaw,
            color,
        )
        if index % 4 == 0 {
            rocky_beach_prism(
                {strand.x, strand.y + .04, strand.z},
                strand.width * 1.8,
                strand.width * 1.3,
                .09,
                strand.yaw,
                color,
            )
        }
    }
    for organism in rocky_beach_plan.organisms[:rocky_beach_plan.organism_count] {
        _, submerged := rocky.water_level(
            rocky.sample(&rocky_beach_plan, organism.x, organism.z),
            rocky_beach_config,
            rocky_beach_tide_phase,
        )
        rocky_beach_draw_organism(organism, submerged)
    }
}

rocky_beach_lab_draw_ui :: proc(_: ^Editor, _: i32, _: i32) {
    panel := canvas.Rectangle{24, 24, 660, 174}
    canvas.DrawRectangleRounded(panel, .09, 8, {10, 27, 34, 235})
    canvas.DrawRectangleRoundedLinesEx(panel, .09, 8, 1, {99, 163, 158, 255})
    title: cstring = rocky_beach_lab_view == .Coast ? "COASTAL ECOLOGY GENERATOR LAB" : "MARINE HABITAT CAPTURE LAB"
    canvas.DrawTextEx(canvas.Font{}, title, {40, 40}, 19, 1, {239, 224, 179, 255})
    tide := rocky.tide_height(rocky_beach_config, rocky_beach_tide_phase)
    state: cstring = tide < 0 ? "LOW" : (tide > rocky_beach_config.tide_range * .48 ? "HIGH" : "MID")
    canvas.DrawTextEx(
        canvas.Font{},
        fmt.ctprintf(
            "SEED %08X   TIDE %s %+4.1fm   PHASE %3.0f%%   RANGE %.1fm",
            rocky_beach_config.seed,
            state,
            tide,
            rocky_beach_tide_phase * 100,
            rocky_beach_config.tide_range,
        ),
        {40, 72},
        12,
        1,
        {177, 221, 213, 255},
    )
    canvas.DrawTextEx(
        canvas.Font{},
        fmt.ctprintf(
            "%d PLATFORM   %d BEACH   %d WRACK   %d SCRUB   RELIEF %.1fm",
            rocky_beach_plan.habitat_counts[int(rocky.Habitat.Rock_Platform)],
            rocky_beach_plan.habitat_counts[int(rocky.Habitat.Pocket_Beach)],
            rocky_beach_plan.wrack_count,
            rocky_beach_plan.habitat_counts[int(rocky.Habitat.Coastal_Scrub)],
            rocky_beach_config.relief,
        ),
        {40, 98},
        12,
        1,
        {189, 203, 167, 255},
    )
    canvas.DrawTextEx(
        canvas.Font{},
        "LEFT/RIGHT SEED   R REROLL   SPACE PAUSE TIDE   Q/E SCRUB",
        {40, 127},
        11,
        1,
        {162, 192, 194, 255},
    )
    canvas.DrawTextEx(
        canvas.Font{},
        "1 ROCKY HEADLANDS   2 EMBAYED COAST   3 LOW COAST   UP/DOWN TIDAL RANGE",
        {40, 151},
        11,
        1,
        {150, 179, 177, 255},
    )
}
