package main

import dunes "../packages/dunes"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:strconv"
import canvas2d "zelda_engine:canvas2d"

DUNES_LAB_DEFAULT_SEED :: u32(0x44554e45)
DUNES_LAB_DEFAULT_WIND_ANGLE :: f32(.08)
DUNES_LAB_DEFAULT_VEGETATION :: f32(.76)
DUNES_LAB_LENGTH :: f32(430)
DUNES_LAB_WIDTH :: f32(155)

Dunes_Lab_Diagnostics :: struct {
    sampled:        int,
    bare:           int,
    stabilized:     int,
    grass_cards:    int,
    maximum_height: f32,
}

Dunes_Lab_Runtime :: struct {
    plan:        dunes.Plan,
    shore:       dunes.Shore_Config,
    diagnostics: Dunes_Lab_Diagnostics,
}

dunes_lab_coast_curve :: #force_inline proc(x: f32) -> f32 {
    return math.sin(x * .018) * 10 + math.sin(x * .047 + .8) * 3.2
}

dunes_lab_coast_slope :: #force_inline proc(x: f32) -> f32 {
    return math.cos(x * .018) * .18 + math.cos(x * .047 + .8) * .1504
}

dunes_lab_shore_distance :: #force_inline proc(x, z: f32) -> f32 {
    vertical_distance := z - dunes_lab_coast_curve(x)
    slope := dunes_lab_coast_slope(x)
    // First-order signed distance to the local coastline tangent. Unlike a
    // vertical offset, this keeps the beach and nearshore profile widths stable
    // through the lab's curved reaches.
    return vertical_distance / f32(math.sqrt(f64(1 + slope * slope)))
}

dunes_lab_water_shallowness :: proc(editor: ^Editor, x, z: f32) -> f32 {
    if editor == nil do return 0
    shore_distance := dunes_lab_shore_distance(x, z)
    coast := dunes.shore_sample(editor.dunes_lab_runtime.shore, shore_distance)
    if shore_distance < 0 do return coast.shallow_water
    t := clamp(shore_distance / f32(8), f32(0), f32(1))
    return 1 - t * t * (3 - 2 * t)
}

dunes_lab_base_height :: proc(editor: ^Editor, x, z: f32) -> f32 {
    if editor == nil do return 0
    shore_distance := dunes_lab_shore_distance(x, z)
    coast := dunes.shore_sample(editor.dunes_lab_runtime.shore, shore_distance)
    if shore_distance <= 0 do return coast.height
    // Let the beach berm settle toward a nearly level inland platform so dune
    // shape and the explicit stabilization mask own the ecology.
    return min(coast.height, f32(.72))
}

dunes_lab_sample :: #force_inline proc(editor: ^Editor, x, z: f32) -> dunes.Sample {
    // Unbend the synthetic coast before querying the reusable straight-segment
    // generator. A surveyed coastline adapter can perform the same local-frame
    // mapping without changing the generator.
    if editor == nil do return {}
    return dunes.sample(&editor.dunes_lab_runtime.plan, {x, dunes_lab_shore_distance(x, z)})
}

dunes_lab_record_diagnostic :: #force_inline proc(runtime: ^Dunes_Lab_Runtime, surface: dunes.Sample) {
    if runtime == nil || !surface.inside do return
    runtime.diagnostics.sampled += 1
    runtime.diagnostics.maximum_height = max(runtime.diagnostics.maximum_height, surface.height_delta)
    if surface.grass_suitability >= .52 {
        runtime.diagnostics.stabilized += 1
    } else if surface.grass_suitability < .18 {
        runtime.diagnostics.bare += 1
    }
}

dunes_lab_finish_diagnostics :: proc(editor: ^Editor) {
    if editor == nil do return
    runtime := &editor.dunes_lab_runtime
    for index in 0 ..< runtime.plan.candidate_count {
        if _, ok := dunes.grass_candidate(&runtime.plan, index); ok {
            runtime.diagnostics.grass_cards += 1
        }
    }
}

dunes_lab_rebuild_diagnostics :: proc(editor: ^Editor) {
    if editor == nil do return
    runtime := &editor.dunes_lab_runtime
    runtime.diagnostics = {}
    data := &editor.project.levels[0]
    for z := 0; z < terrain.TERRAIN_RESOLUTION; z += 4 {
        world_z := data.origin_z + f32(z) * data.cell_size
        for x := 0; x < terrain.TERRAIN_RESOLUTION; x += 4 {
            world_x := data.origin_x + f32(x) * data.cell_size
            surface := dunes_lab_sample(editor, world_x, world_z)
            dunes_lab_record_diagnostic(runtime, surface)
        }
    }
    dunes_lab_finish_diagnostics(editor)
}

dunes_lab_apply_terrain :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.project.sea_level = 0
    runtime := &editor.dunes_lab_runtime
    runtime.diagnostics = {}
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        data := &editor.project.levels[level_index]
        half_grid := f32(terrain.TERRAIN_RESOLUTION - 1) * .5 * data.cell_size
        data.origin_x = -half_grid
        data.origin_z = -half_grid
        for z in 0 ..< terrain.TERRAIN_RESOLUTION {
            world_z := data.origin_z + f32(z) * data.cell_size
            for x in 0 ..< terrain.TERRAIN_RESOLUTION {
                world_x := data.origin_x + f32(x) * data.cell_size
                index := z * terrain.TERRAIN_RESOLUTION + x
                base := dunes_lab_base_height(editor, world_x, world_z)
                surface := dunes_lab_sample(editor, world_x, world_z)
                height := base
                shore_distance := dunes_lab_shore_distance(world_x, world_z)
                coast := dunes.shore_sample(runtime.shore, shore_distance)
                material := -1 - coast.wetness
                if base > 0 && surface.inside {
                    height = max(base, base + surface.height_delta)
                    material = -1 + surface.grass_suitability - coast.wetness
                }
                data.heights[index] = height
                data.material[index] = material
                if level_index == 0 && surface.inside && ((x & 3) == 0) && ((z & 3) == 0) {
                    dunes_lab_record_diagnostic(runtime, surface)
                }
            }
        }
    }
    dunes_lab_finish_diagnostics(editor)
    editor.project.revision += 1
    world_terrain_invalidate_all(editor)
}

dunes_lab_rebuild_runtime :: proc(editor: ^Editor) {
    if editor == nil do return
    config := editor.lab.dunes
    runtime := &editor.dunes_lab_runtime
    wind := dunes.Vec2{math.sin(config.wind_angle), math.cos(config.wind_angle)}
    runtime.shore = {
        sea_level       = 0,
        berm_height     = .95,
        dry_beach_width = 25,
        nearshore_width = 78,
        nearshore_depth = 3.4,
        shelf_width     = 155,
        shelf_depth     = 13,
        bar_strength    = .82,
    }
    runtime.plan = dunes.generate(
        {
            seed = config.seed,
            anchor = {0, 0},
            tangent = {1, 0},
            inland = {0, 1},
            length = DUNES_LAB_LENGTH,
            width = DUNES_LAB_WIDTH,
            wind_direction = wind,
            wind_strength = .72,
            dune_height = 9.2,
            dune_spacing = 34,
            vegetation_strength = config.vegetation,
            shore_fade = 13,
            inland_fade = 25,
        },
    )
    runtime.diagnostics = {}
}

dunes_lab_regenerate :: proc(editor: ^Editor) {
    dunes_lab_rebuild_runtime(editor)
    dunes_lab_apply_terrain(editor)
}

// Fixture and hot-state load rebuild only derived Dunes state. The saved
// terrain, revision, and camera remain authoritative.
dunes_lab_rehydrate :: proc(editor: ^Editor) {
    if editor == nil do return
    if lab_fixture_preflight(editor.lab) != "" do return
    editor.dunes_lab_runtime = {}
    if editor.lab.kind != .Dunes {
        if editor.active_lab_scene == "dunes" do editor.active_lab_scene = ""
        return
    }
    dunes_lab_rebuild_runtime(editor)
    dunes_lab_rebuild_diagnostics(editor)
    editor.active_lab_scene = "dunes"
}

dunes_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    editor.lab = {
        kind = .Dunes,
        dunes = {
            seed = DUNES_LAB_DEFAULT_SEED,
            wind_angle = DUNES_LAB_DEFAULT_WIND_ANGLE,
            vegetation = DUNES_LAB_DEFAULT_VEGETATION,
        },
    }
    if target != "" {
        if parsed, ok := strconv.parse_u64(target, 0); ok do editor.lab.dunes.seed = u32(parsed)
    }
    dunes_lab_regenerate(editor)
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.in_map = false
    editor.capture_world_only = false
    set_pointer_locked(false)
    editor.camera_pose = third_person.camera_look_at({190, 82, -118}, {0, 4.5, 72})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

dunes_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil || editor.lab.kind != .Dunes do return
    config := &editor.lab.dunes
    changed := false
    if canvas2d.IsKeyPressed(.LEFT) {
        config.seed -= 1
        changed = true
    }
    if canvas2d.IsKeyPressed(.RIGHT) {
        config.seed += 1
        changed = true
    }
    if canvas2d.IsKeyPressed(.R) {
        config.seed = dunes.hash(config.seed + 0x9e3779b9)
        changed = true
    }
    if canvas2d.IsKeyPressed(.A) {
        config.wind_angle = max(f32(-.62), config.wind_angle - .08)
        changed = true
    }
    if canvas2d.IsKeyPressed(.D) {
        config.wind_angle = min(f32(.62), config.wind_angle + .08)
        changed = true
    }
    if canvas2d.IsKeyPressed(.G) {
        config.vegetation = max(f32(0), config.vegetation - .1)
        changed = true
    }
    if canvas2d.IsKeyPressed(.H) {
        config.vegetation = min(f32(1), config.vegetation + .1)
        changed = true
    }
    if changed do dunes_lab_regenerate(editor)
}

world_dunes_lab :: proc(editor: ^Editor) {
    if editor == nil do return
    runtime := &editor.dunes_lab_runtime
    for index in 0 ..< runtime.plan.candidate_count {
        candidate, ok := dunes.grass_candidate(&runtime.plan, index)
        if !ok do continue
        x := candidate.position[0]
        z := candidate.position[1] + dunes_lab_coast_curve(x)
        ground := terrain.sample_surface_height(&editor.project, 0, x, z)
        color := canvas2d.Color {
            u8(92 + candidate.tint * 20),
            u8(119 + candidate.tint * 25),
            u8(55 + candidate.tint * 13),
            255,
        }
        world_grass_card(
            {x, ground + candidate.height * .5, z},
            candidate.width,
            candidate.height,
            candidate.tile,
            color,
        )
    }
}

dunes_lab_draw_ui :: proc(editor: ^Editor, _: i32, _: i32) {
    if editor == nil do return
    runtime := &editor.dunes_lab_runtime
    config := editor.lab.dunes
    panel := canvas2d.Rectangle{24, 24, 610, 166}
    canvas2d.DrawRectangleRounded(panel, .10, 8, {28, 31, 23, 232})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {159, 147, 92, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "COASTAL DUNE ECOLOGY LAB", {40, 40}, 19, 1, {242, 227, 183, 255})
    status := fmt.ctprintf(
        "SEED %08X  /  %d RIDGES  /  PEAK %.1fm  /  %d GRASS CARDS",
        config.seed,
        runtime.plan.dune_count,
        runtime.diagnostics.maximum_height,
        runtime.diagnostics.grass_cards,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, status, {40, 70}, 12, 1, {210, 204, 166, 255})
    bare_percent, stable_percent := f32(0), f32(0)
    if runtime.diagnostics.sampled > 0 {
        bare_percent = f32(runtime.diagnostics.bare) / f32(runtime.diagnostics.sampled) * 100
        stable_percent = f32(runtime.diagnostics.stabilized) / f32(runtime.diagnostics.sampled) * 100
    }
    ecology := fmt.ctprintf(
        "WIND %+3.0f deg  /  VEGETATION %3.0f%%  /  BARE %.0f%%  /  STABILIZED %.0f%%",
        config.wind_angle * 180 / math.PI,
        config.vegetation * 100,
        bare_percent,
        stable_percent,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, ecology, {40, 95}, 12, 1, {184, 205, 156, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "LEFT/RIGHT SEED   R REROLL   A/D WIND   G/H GRASS",
        {40, 126},
        11,
        1,
        {191, 190, 164, 255},
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "BEACH  >  ACTIVE SLIP FACES  >  PATCHY CRESTS  >  STABILIZED DUNES",
        {40, 151},
        10,
        1,
        {157, 177, 133, 255},
    )
}

dunes_lab_exit :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.lab = {}
    editor.dunes_lab_runtime = {}
    if editor.active_lab_scene == "dunes" do editor.active_lab_scene = ""
}
