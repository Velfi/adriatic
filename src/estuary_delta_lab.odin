package main

import atmosphere "../packages/atmosphere"
import estuaries "../packages/estuaries"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:strconv"
import "core:time"
import canvas2d "zelda_engine:canvas2d"

ESTUARY_LAB_HALF_X :: f32(620)
ESTUARY_LAB_HALF_Z :: f32(620)

Estuary_Lab_Layer :: enum u8 {
    Elevation,
    Wet_Dry,
    Flow,
    Sediment,
    Erosion,
    Wetland,
    Channels,
}

Estuary_Lab_View :: enum u8 {
    Overview,
    Eye_Level,
}

ESTUARY_LAB_LAYER_NAMES := [7]string {
    "ELEVATION",
    "WET / DRY",
    "FLOW",
    "SEDIMENT",
    "EROSION / DEPOSITION",
    "WETLANDS",
    "CHANNEL ORDER",
}

estuary_lab_config: estuaries.Config
estuary_lab_plan: estuaries.Plan
estuary_lab_layer: Estuary_Lab_Layer
estuary_lab_stale := false
estuary_lab_generation_ms: f32
estuary_lab_view: Estuary_Lab_View

estuary_lab_source_to_world :: proc(x, z: f32, orientation: estuaries.Orientation) -> (f32, f32) {
    switch orientation {
    case .North:
        return x, z
    case .East:
        return z, -x
    case .South:
        return -x, -z
    case .West:
        return -z, x
    }
    return x, z
}

estuary_lab_set_camera_look_at :: proc(editor: ^Editor, eye, target: third_person.Vec3) {
    delta := eye - target
    distance := max(f32(math.sqrt(f64(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z))), f32(1))
    editor.editor_focus = target
    editor.editor_camera = {
        yaw_radians   = f32(math.atan2(f64(delta.x), f64(delta.z))),
        pitch_radians = f32(math.asin(f64(clamp(delta.y / distance, -1, 1)))),
        distance      = distance,
    }
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

estuary_lab_channel_center :: proc(source_z: f32) -> f32 {
    best_x, best_height := f32(0), f32(1e9)
    for sample in 0 ..< estuaries.GRID_WIDTH {
        x := f32(sample) / f32(estuaries.GRID_WIDTH - 1) * 2 - 1
        height := estuaries.sample_elevation_source(&estuary_lab_plan, x, source_z)
        if height < best_height {
            best_x, best_height = x, height
        }
    }
    return best_x
}

estuary_lab_marsh_focus :: proc(source_z: f32) -> f32 {
    best_x, best_score := f32(.18), f32(-1e9)
    for sample in 0 ..< estuaries.GRID_WIDTH {
        x := f32(sample) / f32(estuaries.GRID_WIDTH - 1) * 2 - 1
        // Prefer the right-hand island field so the control panel does not
        // obscure the focal shoreline in the authored view.
        if x < .06 do continue
        world_x, world_z := estuary_lab_source_to_world(x, source_z, estuary_lab_config.orientation)
        wetland := estuaries.sample_wetland(&estuary_lab_plan, world_x, world_z)
        if wetland != .Marsh do continue
        height := estuaries.sample_elevation_source(&estuary_lab_plan, x, source_z)
        score := height - math.abs(x - .22) * 1.4
        if score > best_score do best_x, best_score = x, score
    }
    return best_x
}

estuary_lab_configure_camera :: proc(editor: ^Editor) {
    if editor == nil do return
    if estuary_lab_view == .Eye_Level {
        // Stand at the head of tide and look through the island field.  The
        // former upstream framing ended just before the generated morphology
        // became interesting, presenting only a long empty reach.
        eye_source_z, target_source_z := f32(.03), f32(-.18)
        eye_source_x := estuary_lab_channel_center(eye_source_z)
        target_source_x := estuary_lab_marsh_focus(target_source_z)
        eye_x, eye_z := estuary_lab_source_to_world(eye_source_x, eye_source_z, estuary_lab_config.orientation)
        target_x, target_z := estuary_lab_source_to_world(
            target_source_x,
            target_source_z,
            estuary_lab_config.orientation,
        )
        sea := estuary_lab_plan.config.mean_sea_level
        estuary_lab_set_camera_look_at(
            editor,
            // Stay above the ocean volume's near-surface transition.  This is
            // still a low, human-scale view, but avoids the underwater veil
            // produced when the camera skims the animated water plane.
            {eye_x * ESTUARY_LAB_HALF_X, sea + 8.5, eye_z * ESTUARY_LAB_HALF_Z},
            {target_x * ESTUARY_LAB_HALF_X, sea + 1, target_z * ESTUARY_LAB_HALF_Z},
        )
        return
    }
    estuary_lab_set_camera_look_at(editor, {0, 670, 50}, {0, 0, -210})
}

estuary_lab_height :: proc(world_x, world_z: f32) -> f32 {
    nx, nz := world_x / ESTUARY_LAB_HALF_X, world_z / ESTUARY_LAB_HALF_Z
    source_x, source_z := estuaries.rotate_sample(estuary_lab_plan.config.orientation, nx, nz)
    if math.abs(source_x) > 1 || math.abs(source_z) > 1 {
        config := estuary_lab_plan.config
        if math.abs(source_x) > 1 do return config.mean_sea_level + config.relief
        if source_z < -1 {
            edge := estuaries.sample_elevation_source(&estuary_lab_plan, source_x, -1)
            offshore := -1 - source_z
            return edge - estuaries.smoothstep(clamp(offshore / 1.5, 0, 1)) * 3
        }
        // Continue the inlet upstream from the exact edge samples. Bending
        // the lookup, rather than stamping a second channel, preserves C0
        // continuity and avoids a straight seam at the plan boundary.
        upstream := source_z - 1
        phase := f32(config.seed & 255) * .011
        bend := f32(math.sin(f64(upstream * 1.8 + phase))) * .035 * estuaries.smoothstep(clamp(upstream / .35, 0, 1))
        edge := estuaries.sample_elevation_source(&estuary_lab_plan, source_x - bend, 1)
        if edge < config.mean_sea_level {
            return edge + min(upstream * .08, f32(.35))
        }
        return edge + min(upstream * config.relief * .16, config.relief)
    }
    return estuaries.sample_elevation(&estuary_lab_plan, nx, nz)
}

estuary_lab_material :: proc(height: f32) -> f32 {
    sea := estuary_lab_plan.config.mean_sea_level
    elevation := height - sea
    // Keep the intertidal profile visibly stratified at human height: pale
    // depositional bars above the tide line, dark saturated mud at the water
    // edge, and ordinary soil/grass once the floodplain is safely dry.
    tidal_band := max(estuary_lab_plan.config.tidal_range * .38, f32(.35))
    if elevation >= tidal_band + .55 do return 0
    wetness := 1 - estuaries.smoothstep(clamp((elevation + .08) / tidal_band, 0, 1))
    bar_fade := 1 - estuaries.smoothstep(clamp((elevation - tidal_band) / .55, 0, 1))
    return -bar_fade - wetness * .72
}

estuary_lab_terrain_sample :: proc(_: ^Editor, world_x, world_z: f32) -> Lab_Terrain_Sample {
    height := estuary_lab_height(world_x, world_z)
    return {height = height, material = estuary_lab_material(height)}
}

estuary_lab_apply_terrain :: proc(editor: ^Editor) {
    _ = lab_terrain_load(
        editor,
        {
            half_extent_x    = ESTUARY_LAB_HALF_X,
            // Leave room for the optional source channel north of the map.
            half_extent_z    = ESTUARY_LAB_HALF_Z * 1.35,
            sea_level        = estuary_lab_plan.config.mean_sea_level,
            outside_height   = estuary_lab_plan.config.mean_sea_level - 4,
            outside_material = -1.5,
        },
        estuary_lab_terrain_sample,
    )
}

estuary_lab_regenerate :: proc(editor: ^Editor) -> bool {
    estuaries.destroy(&estuary_lab_plan)
    start := time.tick_now()
    estuary_lab_plan = estuaries.generate(estuary_lab_config)
    estuary_lab_generation_ms = f32(time.duration_seconds(time.tick_since(start)) * 1000)
    if len(estuary_lab_plan.elevation) != estuaries.CELL_COUNT do return false
    estuary_lab_config = estuary_lab_plan.config
    // Preserve the requested seed in controls even when candidate selection
    // chooses a later derived seed.
    estuary_lab_config.seed = estuary_lab_plan.requested_seed
    estuary_lab_apply_terrain(editor)
    estuary_lab_stale = false
    return true
}

estuary_delta_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    estuary_lab_config = estuaries.default_config()
    estuary_lab_view = target == "eye" ? .Eye_Level : .Overview
    if target != "" {
        if parsed, ok := strconv.parse_u64(target, 0); ok do estuary_lab_config.seed = u32(parsed)
    }
    if !estuary_lab_regenerate(editor) do return false
    editor.postale_visible, editor.libellula_visible = false, false
    editor.in_map = false
    editor.capture_world_only = false
    atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 35)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    set_pointer_locked(false)
    estuary_lab_configure_camera(editor)
    return true
}

estuary_delta_lab_exit :: proc(_: ^Editor) { estuaries.destroy(&estuary_lab_plan) }

world_estuary_delta_lab :: proc(_: ^Editor) {
    if len(estuary_lab_plan.elevation) != estuaries.CELL_COUNT do return
    spacing := f32(3.6)
    samples := int(ESTUARY_LAB_HALF_X * 2 / spacing)
    for z_index in 0 ..= samples {
        world_z := -ESTUARY_LAB_HALF_Z + f32(z_index) * spacing
        for x_index in 0 ..= samples {
            mixed := estuaries.hash(
                estuary_lab_plan.selected_seed ~ u32(x_index + 1) * 0x9e3779b9 ~ u32(z_index + 1) * 0x85ebca6b,
            )
            // Broad deterministic bands make beds and openings instead of a
            // salt-and-pepper distribution of isolated plants.
            patch_field :=
                f32(math.sin(f64(world_z * .021 + f32(estuary_lab_plan.selected_seed & 255) * .031))) +
                f32(math.sin(f64(f32(x_index) * .093 - f32(z_index) * .041))) * .55
            if patch_field < -.28 || (mixed >> 28) == 0 do continue
            jitter_x := (f32(mixed & 255) / 255 - .5) * spacing * .72
            jitter_z := (f32((mixed >> 8) & 255) / 255 - .5) * spacing * .72
            world_x := -ESTUARY_LAB_HALF_X + f32(x_index) * spacing + jitter_x
            sample_z := world_z + jitter_z
            nx, nz := world_x / ESTUARY_LAB_HALF_X, sample_z / ESTUARY_LAB_HALF_Z
            if estuaries.sample_wetland(&estuary_lab_plan, nx, nz) != .Marsh do continue
            ground := estuary_lab_height(world_x, sample_z)
            if ground <= estuary_lab_plan.config.mean_sea_level + .04 do continue
            height := 2.20 + f32((mixed >> 16) & 255) / 255 * 2.20
            width := 1.65 + f32((mixed >> 24) & 255) / 255 * 1.25
            world_marsh_card({world_x, ground + height * .5, sample_z}, width, height, int(mixed % 16))
            if (mixed & 3) != 0 {
                companion_height := height * (.72 + f32((mixed >> 10) & 31) / 31 * .24)
                companion_x := world_x + (f32((mixed >> 5) & 31) / 31 - .5) * 2.4
                companion_z := sample_z + (f32((mixed >> 13) & 31) / 31 - .5) * 2.4
                companion_ground := estuary_lab_height(companion_x, companion_z)
                world_marsh_card(
                    {companion_x, companion_ground + companion_height * .5, companion_z},
                    width * .82,
                    companion_height,
                    int((mixed >> 4) % 16),
                )
            }
        }
    }
}

estuary_lab_button :: proc(x, y, width: f32) -> canvas2d.Rectangle { return {x, y, width, 28} }

estuary_lab_slider_bounds :: proc(index: int) -> canvas2d.Rectangle { return {40, 244 + f32(index) * 34, 250, 18} }

estuary_lab_slider_update :: proc(bounds: canvas2d.Rectangle, value: ^f32, lower, upper: f32) -> bool {
    mouse := canvas2d.GetMousePosition()
    if !canvas2d.IsMouseButtonDown(.LEFT) || !canvas2d.CheckCollisionPointRec(mouse, {bounds.x - 5, bounds.y - 8, bounds.width + 10, bounds.height + 16}) do return false
    next := lower + clamp((mouse.x - bounds.x) / bounds.width, 0, 1) * (upper - lower)
    if next == value^ do return false
    value^ = next
    return true
}

estuary_delta_lab_process_input :: proc(editor: ^Editor) {
    changed := false
    if canvas2d.IsKeyPressed(.LEFT) { estuary_lab_config.seed -= 1; changed = true }
    if canvas2d.IsKeyPressed(.RIGHT) { estuary_lab_config.seed += 1; changed = true }
    if canvas2d.IsKeyPressed(.ONE) { estuary_lab_config.archetype = .Tidal_Estuary; changed = true }
    if canvas2d.IsKeyPressed(.TWO) { estuary_lab_config.archetype = .Distributary_Delta; changed = true }
    if canvas2d.IsKeyPressed(.D) do estuary_lab_layer = Estuary_Lab_Layer((int(estuary_lab_layer) + 1) % len(ESTUARY_LAB_LAYER_NAMES))
    if canvas2d.IsKeyPressed(.C) {
        estuary_lab_view = estuary_lab_view == .Overview ? .Eye_Level : .Overview
        estuary_lab_configure_camera(editor)
    }
    regenerate := canvas2d.IsKeyPressed(.ENTER)
    if canvas2d.IsKeyPressed(.R) {
        estuary_lab_config.seed = estuaries.hash(estuary_lab_config.seed + 0x9e3779b9)
        regenerate = true
    }
    mouse := canvas2d.GetMousePosition()
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        if canvas2d.CheckCollisionPointRec(mouse, estuary_lab_button(40, 164, 118)) do regenerate = true
        if canvas2d.CheckCollisionPointRec(mouse, estuary_lab_button(168, 164, 118)) {
            estuary_lab_config = estuaries.default_config()
            changed = true
        }
        if canvas2d.CheckCollisionPointRec(mouse, estuary_lab_button(40, 202, 118)) {
            estuary_lab_config.archetype =
                estuary_lab_config.archetype == .Tidal_Estuary ? .Distributary_Delta : .Tidal_Estuary
            changed = true
        }
        if canvas2d.CheckCollisionPointRec(mouse, estuary_lab_button(168, 202, 118)) {
            estuary_lab_config.orientation = estuaries.Orientation((int(estuary_lab_config.orientation) + 1) % 4)
            changed = true
        }
    }
    changed = estuary_lab_slider_update(estuary_lab_slider_bounds(0), &estuary_lab_config.branching, 0, 1) || changed
    changed =
        estuary_lab_slider_update(estuary_lab_slider_bounds(1), &estuary_lab_config.mouth_width, .08, .45) || changed
    changed =
        estuary_lab_slider_update(estuary_lab_slider_bounds(2), &estuary_lab_config.sediment_load, 0, 1) || changed
    changed = estuary_lab_slider_update(estuary_lab_slider_bounds(3), &estuary_lab_config.relief, 2, 30) || changed
    changed =
        estuary_lab_slider_update(estuary_lab_slider_bounds(4), &estuary_lab_config.mean_sea_level, -5, 5) || changed
    changed = estuary_lab_slider_update(estuary_lab_slider_bounds(5), &estuary_lab_config.tidal_range, 0, 4) || changed
    if changed do estuary_lab_stale = true
    if regenerate do _ = estuary_lab_regenerate(editor)
}

estuary_lab_color :: proc(index: int) -> canvas2d.Color {
    elevation := estuary_lab_plan.elevation[index]
    sea := estuary_lab_plan.config.mean_sea_level
    switch estuary_lab_layer {
    case .Elevation:
        if elevation < sea do return {24, u8(clamp(90 + (sea - elevation) * 10, 70, 180)), 178, 255}
        shade := u8(clamp(86 + (elevation - sea) * 8, 86, 220))
        return {shade, u8(clamp(f32(shade) + 18, 0, 255)), 92, 255}
    case .Wet_Dry:
        return elevation <= sea ? canvas2d.Color{38, 145, 188, 255} : canvas2d.Color{174, 158, 100, 255}
    case .Flow:
        speed := f32(
            math.sqrt(
                f64(
                    estuary_lab_plan.flow_x[index] * estuary_lab_plan.flow_x[index] +
                    estuary_lab_plan.flow_z[index] * estuary_lab_plan.flow_z[index],
                ),
            ),
        )
        return {30, u8(clamp(speed * 220, 30, 245)), 220, 255}
    case .Sediment:
        value := u8(clamp(estuary_lab_plan.sediment[index] * 500, 0, 255))
        return {value, u8(f32(value) * .72), 45, 255}
    case .Erosion:
        value := estuary_lab_plan.erosion_deposition[index]
        if value < 0 do return {u8(clamp(-value * 220, 20, 255)), 70, 45, 255}
        return {45, 90, u8(clamp(value * 220, 20, 255)), 255}
    case .Wetland:
        colors := [6]canvas2d.Color {
            {91, 94, 72, 255},
            {32, 112, 171, 255},
            {153, 125, 74, 255},
            {82, 139, 88, 255},
            {203, 177, 105, 255},
            {25, 78, 139, 255},
        }
        return colors[int(estuary_lab_plan.wetland[index])]
    case .Channels:
        order := estuary_lab_plan.channel_order[index]
        return order == 0 ? canvas2d.Color{64, 76, 70, 255} : canvas2d.Color{35, u8(110 + order * 38), 220, 255}
    }
    return {255, 0, 255, 255}
}

estuary_lab_draw_button :: proc(bounds: canvas2d.Rectangle, label: cstring) {
    hover := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
    canvas2d.DrawRectangleRounded(
        bounds,
        .20,
        6,
        hover ? canvas2d.Color{49, 111, 118, 250} : canvas2d.Color{31, 69, 77, 245},
    )
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .20, 6, 1, {103, 178, 177, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, label, {bounds.x + 9, bounds.y + 8}, 10, 1, {240, 229, 187, 255})
}

estuary_lab_draw_slider :: proc(index: int, label: cstring, value, lower, upper: f32) {
    bounds := estuary_lab_slider_bounds(index)
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf("%s  %.2f", label, value),
        {bounds.x, bounds.y - 13},
        10,
        1,
        {190, 216, 211, 255},
    )
    canvas2d.DrawRectangleRec(bounds, {25, 58, 64, 255})
    canvas2d.DrawRectangleRec(
        {bounds.x, bounds.y, bounds.width * clamp((value - lower) / (upper - lower), 0, 1), bounds.height},
        {67, 151, 148, 255},
    )
}

estuary_delta_lab_draw_ui :: proc(_: ^Editor, width, _: i32) {
    panel := canvas2d.Rectangle{24, 24, 288, 446}
    canvas2d.DrawRectangleRounded(panel, .06, 8, {8, 26, 37, 236})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .06, 8, 1, {94, 156, 169, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "ESTUARY / DELTA LAB", {40, 40}, 18, 1, {242, 231, 188, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf(
            "%s%s",
            estuaries.archetype_name(estuary_lab_config.archetype),
            estuary_lab_stale ? "  • STALE" : "",
        ),
        {40, 70},
        11,
        1,
        estuary_lab_stale ? canvas2d.Color{244, 164, 91, 255} : canvas2d.Color{166, 220, 169, 255},
    )
    view_name := estuary_lab_view == .Overview ? "OVERVIEW" : "EYE"
    canvas2d.DrawTextEx(canvas2d.Font{}, fmt.ctprintf("%s [C]", view_name), {244, 70}, 9, 1, {153, 202, 202, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf("REQUEST %08X  SELECTED %08X", estuary_lab_plan.requested_seed, estuary_lab_plan.selected_seed),
        {40, 92},
        10,
        1,
        {188, 219, 217, 255},
    )
    d := &estuary_lab_plan.diagnostics
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf(
            "%s  TRY %d  %.1f ms",
            estuaries.rejection_text(d.rejection_mask),
            estuary_lab_plan.attempts,
            estuary_lab_generation_ms,
        ),
        {40, 112},
        10,
        1,
        estuary_lab_plan.valid ? canvas2d.Color{154, 220, 148, 255} : canvas2d.Color{245, 154, 116, 255},
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf(
            "OUT %d  ISL %d  NAV %.1f%%  WET %.1f%%",
            d.outlet_count,
            d.island_count,
            d.navigable_fraction * 100,
            d.wetland_fraction * 100,
        ),
        {40, 132},
        10,
        1,
        {188, 219, 217, 255},
    )
    estuary_lab_draw_button(estuary_lab_button(40, 164, 118), "REGENERATE [ENTER]")
    estuary_lab_draw_button(estuary_lab_button(168, 164, 118), "RESET DEFAULTS")
    estuary_lab_draw_button(
        estuary_lab_button(40, 202, 118),
        estuary_lab_config.archetype == .Tidal_Estuary ? "MODE: ESTUARY" : "MODE: DELTA",
    )
    estuary_lab_draw_button(
        estuary_lab_button(168, 202, 118),
        fmt.ctprintf("ORIENT: %d", int(estuary_lab_config.orientation)),
    )
    estuary_lab_draw_slider(0, "BRANCHING", estuary_lab_config.branching, 0, 1)
    estuary_lab_draw_slider(1, "MOUTH WIDTH", estuary_lab_config.mouth_width, .08, .45)
    estuary_lab_draw_slider(2, "SEDIMENT", estuary_lab_config.sediment_load, 0, 1)
    estuary_lab_draw_slider(3, "RELIEF m", estuary_lab_config.relief, 2, 30)
    estuary_lab_draw_slider(4, "SEA LEVEL m", estuary_lab_config.mean_sea_level, -5, 5)
    estuary_lab_draw_slider(5, "TIDAL RANGE m", estuary_lab_config.tidal_range, 0, 4)
    if estuary_lab_view == .Eye_Level do return
    preview_w := f32(384)
    preview_h := preview_w * f32(estuaries.GRID_HEIGHT) / f32(estuaries.GRID_WIDTH)
    origin := canvas2d.Vector2{f32(width) - preview_w - 24, 24}
    canvas2d.DrawRectangleRec({origin.x - 8, origin.y - 8, preview_w + 16, preview_h + 38}, {8, 26, 37, 236})
    cell_w, cell_h := preview_w / estuaries.GRID_WIDTH, preview_h / estuaries.GRID_HEIGHT
    for z in 0 ..< estuaries.GRID_HEIGHT {
        for x in 0 ..< estuaries.GRID_WIDTH {
            i := z * estuaries.GRID_WIDTH + x
            canvas2d.DrawRectangleRec(
                {
                    origin.x + f32(x) * cell_w,
                    origin.y + f32(estuaries.GRID_HEIGHT - 1 - z) * cell_h,
                    cell_w + .3,
                    cell_h + .3,
                },
                estuary_lab_color(i),
            )
        }
    }
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf("%s  [D]", ESTUARY_LAB_LAYER_NAMES[int(estuary_lab_layer)]),
        {origin.x, origin.y + preview_h + 10},
        11,
        1,
        {207, 224, 213, 255},
    )
}
