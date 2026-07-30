package main

import islands "../packages/islands"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:strconv"
import rl "zelda_engine:canvas2d"

MARKOV_ISLAND_DEFAULT_SEED :: u32(0x49534c45)
MARKOV_ISLAND_HALF_X :: f32(620)
MARKOV_ISLAND_HALF_Z :: f32(420)
MARKOV_ISLAND_SHELF_CELLS :: f32(22)
MARKOV_ISLAND_OCEAN_DEPTH :: f32(18)
MARKOV_ISLAND_SHORE_DEPTH :: f32(1.35)

markov_island_seed := MARKOV_ISLAND_DEFAULT_SEED
markov_island_plan: islands.Plan

markov_island_smooth_weight :: #force_inline proc(value: f32) -> f32 {
    t := clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
}

markov_island_random_lattice :: #force_inline proc(x, z: f32, seed: u32) -> f32 {
    phase := f32(seed & 0xffff) * .0137 + f32(seed >> 16) * .0191
    wave := f32(math.sin(f64(x * 127.1 + z * 311.7 + phase))) * 43758.547
    return wave - f32(math.floor(f64(wave)))
}

markov_island_value_noise :: proc(x, z: f32, seed: u32) -> f32 {
    x0 := f32(math.floor(f64(x)))
    z0 := f32(math.floor(f64(z)))
    tx := markov_island_smooth_weight(x - x0)
    tz := markov_island_smooth_weight(z - z0)
    a := markov_island_random_lattice(x0, z0, seed)
    b := markov_island_random_lattice(x0 + 1, z0, seed)
    c := markov_island_random_lattice(x0, z0 + 1, seed)
    d := markov_island_random_lattice(x0 + 1, z0 + 1, seed)
    lower := a + (b - a) * tx
    upper := c + (d - c) * tx
    return lower + (upper - lower) * tz
}

markov_island_shelf_noise :: proc(nx, nz: f32) -> f32 {
    seed := markov_island_plan.selected_seed
    broad := markov_island_value_noise(nx * 3.5, nz * 3.5, seed)
    detail := markov_island_value_noise(nx * 8.5 + 19.7, nz * 8.5 - 7.3, seed ~ 0x9e3779b9)
    return (broad * .72 + detail * .28) * 2 - 1
}

markov_island_height :: proc(world_x, world_z: f32) -> f32 {
    nx, nz := world_x / MARKOV_ISLAND_HALF_X, world_z / MARKOV_ISLAND_HALF_Z
    distance := islands.sample_signed_distance(&markov_island_plan, nx, nz)
    if distance >= 0 {
        // A broad, gently irregular shelf lets shallow water follow the actual
        // coast while sinking the outer terrain beneath the ocean surface.
        // Seeded value noise changes the offshore slope without moving the
        // shoreline, and remains stable when an island seed is regenerated.
        shelf_noise := markov_island_shelf_noise(nx, nz)
        shelf_width := MARKOV_ISLAND_SHELF_CELLS * (1 + shelf_noise * .12)
        shelf_progress := markov_island_smooth_weight(distance / shelf_width)
        // Hold the inner shelf near the sunlit shore depth, then roll into a
        // more decisive outer drop. This exaggerates the turquoise coastal
        // halo without turning the dry coast into a uniform buffer shape.
        depth_weight := shelf_progress * shelf_progress
        deep_water := MARKOV_ISLAND_OCEAN_DEPTH * (1 + shelf_noise * .08)
        // Keep the entire wet heightfield below the editor's ocean plane.
        // Otherwise the first part of the slope becomes a faceted cyan surface
        // outline instead of submerged bathymetry.
        return -(MARKOV_ISLAND_SHORE_DEPTH + (deep_water - MARKOV_ISLAND_SHORE_DEPTH) * depth_weight)
    }
    return islands.sample_elevation(&markov_island_plan, nx, nz)
}

markov_island_apply_terrain :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.project.sea_level = 0
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        data := &editor.project.levels[level_index]
        // The ordinary project centers its fine authored levels on the
        // gameplay islands. This lab generates at the world origin, so center
        // every stored level there as well; otherwise only the coarsest level
        // contains the silhouette and the shoreline collapses to a few large
        // triangles.
        half_grid := f32(terrain.TERRAIN_RESOLUTION - 1) * .5 * data.cell_size
        data.origin_x = -half_grid
        data.origin_z = -half_grid
        for z in 0 ..< terrain.TERRAIN_RESOLUTION {
            world_z := data.origin_z + f32(z) * data.cell_size
            for x in 0 ..< terrain.TERRAIN_RESOLUTION {
                world_x := data.origin_x + f32(x) * data.cell_size
                index := z * terrain.TERRAIN_RESOLUTION + x
                data.heights[index] = markov_island_height(world_x, world_z)
                data.material[index] = 0
            }
        }
    }
    editor.project.revision += 1
    // Clipmap geometry is keyed by terrain_revision, not Project.revision.
    // Regeneration replaces the full heightfield, so invalidate every cached
    // level rather than waiting for camera movement to expose the new data.
    world_terrain_invalidate_all(editor)
}

markov_island_regenerate :: proc(editor: ^Editor) -> bool {
    islands.destroy(&markov_island_plan)
    markov_island_plan = islands.generate(markov_island_seed)
    if len(markov_island_plan.cleaned) != islands.CELL_COUNT do return false
    markov_island_apply_terrain(editor)
    return true
}

markov_island_reroll_button_bounds :: proc() -> rl.Rectangle {
    return {40, 142, 156, 36}
}

markov_island_roll_seed :: proc() {
    // Every press requests a different candidate while the displayed seed
    // remains sufficient to reproduce any result.
    markov_island_seed = islands.hash(markov_island_seed + 0x9e3779b9)
}

markov_island_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    markov_island_seed = MARKOV_ISLAND_DEFAULT_SEED
    if target != "" {
        if parsed, ok := strconv.parse_u64(target, 0); ok do markov_island_seed = u32(parsed)
    }
    if !markov_island_regenerate(editor) do return false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.in_map = false
    editor.capture_world_only = false
    set_pointer_locked(false)
    editor.camera_pose = third_person.camera_look_at({440, 420, 540}, {0, 8, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

markov_island_lab_process_input :: proc(editor: ^Editor) {
    changed := false
    if rl.IsKeyPressed(.LEFT) {
        markov_island_seed -= 1
        changed = true
    }
    if rl.IsKeyPressed(.RIGHT) {
        markov_island_seed += 1
        changed = true
    }
    reroll := rl.IsKeyPressed(.R)
    if rl.IsMouseButtonPressed(.LEFT) &&
       rl.CheckCollisionPointRec(rl.GetMousePosition(), markov_island_reroll_button_bounds()) {
        reroll = true
    }
    if reroll {
        markov_island_roll_seed()
        changed = true
    }
    if changed do _ = markov_island_regenerate(editor)
}

markov_island_lab_exit :: proc(_: ^Editor) {
    islands.destroy(&markov_island_plan)
}

markov_island_contour_color :: proc(kind: islands.Contour_Kind) -> rl.Color {
    switch kind {
    case .Main_Coast:
        return {246, 220, 148, 255}
    case .Lake:
        return {104, 208, 233, 255}
    case .Skerry:
        return {234, 150, 103, 255}
    }
    return {255, 255, 255, 255}
}

markov_island_draw_diagnostic :: proc(width: i32) {
    preview_width := f32(384)
    preview_height := preview_width * f32(islands.GRID_HEIGHT) / f32(islands.GRID_WIDTH)
    origin := rl.Vector2{f32(width) - preview_width - 24, 24}
    panel := rl.Rectangle{origin.x - 10, origin.y - 10, preview_width + 20, preview_height + 45}
    rl.DrawRectangleRounded(panel, .06, 8, {8, 26, 37, 232})
    rl.DrawRectangleRoundedLinesEx(panel, .06, 8, 1, {94, 156, 169, 255})
    cell_w := preview_width / f32(islands.GRID_WIDTH)
    cell_h := preview_height / f32(islands.GRID_HEIGHT)
    for z in 0 ..< islands.GRID_HEIGHT {
        run_start := -1
        for x in 0 ..= islands.GRID_WIDTH {
            land := x < islands.GRID_WIDTH && markov_island_plan.cleaned[z * islands.GRID_WIDTH + x] == .Land
            if land && run_start < 0 do run_start = x
            if !land && run_start >= 0 {
                rl.DrawRectangleRec(
                    {
                        origin.x + f32(run_start) * cell_w,
                        origin.y + f32(z) * cell_h,
                        f32(x - run_start) * cell_w,
                        cell_h + .35,
                    },
                    {74, 123, 88, 255},
                )
                run_start = -1
            }
        }
    }
    for contour in markov_island_plan.contours {
        color := markov_island_contour_color(contour.kind)
        for index in 0 ..< len(contour.points) {
            a := contour.points[index]
            b := contour.points[(index + 1) % len(contour.points)]
            rl.DrawLineEx(
                {origin.x + a.x * cell_w, origin.y + a.z * cell_h},
                {origin.x + b.x * cell_w, origin.y + b.z * cell_h},
                1.5,
                color,
            )
        }
    }
    rl.DrawTextEx(
        rl.Font{},
        "COAST   LAKES   SKERRIES",
        {origin.x, origin.y + preview_height + 10},
        11,
        1,
        {199, 218, 213, 255},
    )
}

markov_island_rejection_text :: proc(mask: u32) -> cstring {
    if mask == 0 do return "VALID"
    if mask & islands.REJECT_AREA != 0 do return "REJECTED: LAND AREA"
    if mask & islands.REJECT_BORDER != 0 do return "REJECTED: BORDER CONTACT"
    if mask & islands.REJECT_FRAGMENTATION != 0 do return "REJECTED: FRAGMENTATION"
    if mask & islands.REJECT_NECKS != 0 do return "REJECTED: NARROW NECKS"
    return "REJECTED: CONTOURS"
}

markov_island_lab_draw_ui :: proc(_: ^Editor, width, _: i32) {
    panel := rl.Rectangle{24, 24, 570, 204}
    rl.DrawRectangleRounded(panel, .10, 8, {8, 26, 37, 232})
    rl.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {94, 156, 169, 255})
    rl.DrawTextEx(rl.Font{}, "MARKOV ISLAND SILHOUETTE LAB", {40, 40}, 19, 1, {242, 231, 188, 255})
    status := fmt.ctprintf(
        "REQUEST %08X  SELECTED %08X  TRY %d/%d  SCORE %.3f",
        markov_island_plan.requested_seed,
        markov_island_plan.selected_seed,
        markov_island_plan.attempts,
        islands.MAX_CANDIDATE_ATTEMPTS,
        markov_island_plan.score,
    )
    rl.DrawTextEx(rl.Font{}, status, {40, 70}, 12, 1, {188, 219, 217, 255})
    diagnostics := &markov_island_plan.diagnostics
    metrics := fmt.ctprintf(
        "LAND %d  COAST %.3f  LAKES %d  SKERRIES %d  BLUFF %d  PEAK %.1fm",
        diagnostics.land_cells,
        diagnostics.coastline_complexity,
        diagnostics.lake_count,
        diagnostics.skerry_count,
        diagnostics.bluff_cells,
        diagnostics.maximum_elevation,
    )
    rl.DrawTextEx(rl.Font{}, metrics, {40, 94}, 12, 1, {188, 219, 217, 255})
    validity_color := markov_island_plan.valid ? rl.Color{154, 220, 148, 255} : rl.Color{245, 154, 116, 255}
    shape_status := fmt.ctprintf(
        "%s     %s  ASPECT %.2f  RECT %.2f",
        markov_island_rejection_text(diagnostics.rejection_mask),
        islands.shape_archetype_name(markov_island_plan.shape),
        diagnostics.aspect_ratio,
        diagnostics.rectangularity,
    )
    rl.DrawTextEx(rl.Font{}, shape_status, {40, 118}, 12, 1, validity_color)
    button := markov_island_reroll_button_bounds()
    hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), button)
    button_fill: rl.Color = hovered ? {52, 125, 131, 248} : {34, 79, 85, 244}
    rl.DrawRectangleRounded(button, .22, 8, button_fill)
    rl.DrawRectangleRoundedLinesEx(button, .22, 8, 1, {112, 198, 194, 255})
    rl.DrawTextEx(rl.Font{}, "ROLL NEW ISLAND  [R]", {button.x + 13, button.y + 12}, 11, 1, {242, 231, 188, 255})
    rl.DrawTextEx(rl.Font{}, "LEFT / RIGHT: STEP SEED", {40, 194}, 11, 1, {175, 190, 190, 255})
    markov_island_draw_diagnostic(width)
}
