package main

import architecture "../packages/architecture"
import ruins "../packages/ruins"
import terrain "../packages/terrain"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

// Frozen bounds for validating legacy Fixture data. No live GLB catalog exists.
GREEK_ASSET_CAPACITY :: 8
GREEK_PLACEMENT_CAPACITY :: 64

Greek_Placement :: struct {
    asset_index: int,
    x, z:        f32,
    base_y:      f32,
    rotation:    f32,
    scale:       f32,
}

RUIN_STAMP_DEFAULT_SEED :: u32(0x5255494e)

ruin_stamp_candidate :: proc(editor: ^Editor, world_x, world_z: f32) -> (terrain.Structure, bool) {
    if editor == nil do return {}, false
    snap := terrain.BASE_CELL_SIZE
    x := f32(math.round(f64(world_x / snap))) * snap
    z := f32(math.round(f64(world_z / snap))) * snap
    site := settlement_ruin_profile(&editor.project, {x, z})
    seed := RUIN_STAMP_DEFAULT_SEED ~ editor.ruin_stamp_seed_offset * u32(0x27d4eb2d)
    region := editor.ruin_stamp_aegean ? Settlement_Region.Aegean : .Adriatic
    culture := settlement_ruin_culture(region, seed)
    mode := editor.ruin_stamp_complex ? ruins.Mode.Complex : .Ruin
    generated := ruins.generate_for_site(culture, mode, seed, site)
    width, depth := settlement_ruin_bounds(&generated)
    empty_city: architecture.City_Plan
    if !settlement_brush_point_developable(&editor.project, {x, z}, SETTLEMENT_VILLAGE.max_slope) ||
       !settlement_structure_clear(&editor.project, &empty_city, x, z, width, depth, 0, 3) {
        return {}, false
    }
    structure := terrain.structure_make(
        x,
        z,
        width,
        depth,
        terrain.sample_height(&editor.project, 0, x, z),
        max(generated.elevation_range + f32(8), f32(12)),
    )
    structure.kind = .Ruins
    structure.seed = seed
    structure.color = {
        editor.ruin_stamp_aegean ? u8(1) : u8(0),
        editor.ruin_stamp_complex ? u8(1) : u8(0),
        u8(site.profile),
        255,
    }
    return structure, true
}

ruin_stamp_update_preview :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || !editor.greek_placement_mode || editor.in_map || !cursor_hit {
        if editor != nil do editor.ruin_stamp_preview_valid = false
        return
    }
    editor.ruin_stamp_preview, editor.ruin_stamp_preview_valid = ruin_stamp_candidate(editor, world_x, world_z)
}

ruin_stamp_process_input :: proc(editor: ^Editor, cursor_hit: bool) {
    if editor == nil || !editor.greek_placement_mode || editor.in_map || !cursor_hit do return
    if canvas2d.IsMouseButtonPressed(.RIGHT) {
        editor.ruin_stamp_seed_offset += 1
        editor.ruin_stamp_preview_valid = false
        return
    }
    if !canvas2d.IsMouseButtonPressed(.LEFT) || !editor.ruin_stamp_preview_valid do return
    structure_history_push_undo(editor)
    if index := terrain.add_structure(&editor.project, editor.ruin_stamp_preview); index >= 0 {
        // add_structure assigns an identity-derived default seed. Restore the
        // authored variation so the placed ruin exactly matches its preview.
        editor.project.structures[index].seed = editor.ruin_stamp_preview.seed
    }
    editor.ruin_stamp_preview_valid = false
}
