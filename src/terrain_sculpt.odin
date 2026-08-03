package main

import terrain "../packages/terrain"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

Terrain_Sculpt_Mode :: enum u8 {
    Shape,
    Level,
    Grade,
    Terrace,
    Erode,
}

Terrain_Sculpt_Session :: struct {
    active:                         bool,
    valid:                          bool,
    changed:                        bool,
    owner:                          terrain.Island_ID,
    start_x, start_z:               f32,
    current_x, current_z:           f32,
    start_screen_y:                 f32,
    sampled_height:                 f32,
    displacement:                   f32,
    dirty_x, dirty_z, dirty_radius: f32,
    base:                           ^Terrain_History_State,
}

Terrain_Sculpt_State :: struct {
    mode:    Terrain_Sculpt_Mode,
    area:    bool,
    session: Terrain_Sculpt_Session,
}

terrain_sculpt_owns_direct_brush :: #force_inline proc(editor: ^Editor) -> bool {
    return editor != nil && editor.authoring_tool == .Sculpt && editor.terrain_sculpt.mode != .Shape
}

terrain_sculpt_restore_base :: proc(editor: ^Editor) {
    if editor == nil || !editor.terrain_sculpt.session.active do return
    source := editor.terrain_sculpt.session.base
    if source == nil do return
    editor.project.levels = source.levels
    editor.project.sea_level = source.sea_level
    editor.project.revision = source.revision
}

terrain_sculpt_reseat_structures :: proc(editor: ^Editor, x, z, radius: f32) {
    if editor == nil do return
    radius_squared := radius * radius
    for &structure in editor.project.structures[:editor.project.structure_count] {
        dx, dz := structure.center_x - x, structure.center_z - z
        if dx * dx + dz * dz > radius_squared do continue
        structure.base_y = terrain.sample_surface_height(&editor.project, 0, structure.center_x, structure.center_z)
    }
}

terrain_sculpt_area_geometry :: proc(
    editor: ^Editor,
    session: ^Terrain_Sculpt_Session,
) -> terrain.Terrain_Operator_Area {
    return {
        owner = session.owner,
        start_x = session.start_x,
        start_z = session.start_z,
        end_x = session.current_x,
        end_z = session.current_z,
        target_height = session.sampled_height + session.displacement,
        boundary_blend = max(editor.radius * .2, f32(2)),
    }
}

terrain_sculpt_apply :: proc(editor: ^Editor, session: ^Terrain_Sculpt_Session) -> bool {
    if editor == nil || session == nil || !session.active || !session.valid do return false
    amount := clamp(editor.strength, f32(0), f32(1))
    switch editor.terrain_sculpt.mode {
    case .Shape:
        return false
    case .Level:
        if editor.terrain_sculpt.area {
            return terrain.apply_level_area_operator(
                &editor.project,
                terrain_sculpt_area_geometry(editor, session),
                amount,
                editor.hardness,
            )
        }
        return terrain.apply_level_operator(
            &editor.project,
            session.owner,
            session.start_x,
            session.start_z,
            editor.radius,
            session.sampled_height + session.displacement,
            amount,
            editor.hardness,
        )
    case .Grade:
        end_height := terrain.sample_surface_height(&editor.project, 0, session.current_x, session.current_z)
        return terrain.apply_grade_operator(
            &editor.project,
            session.owner,
            session.start_x,
            session.start_z,
            session.sampled_height,
            session.current_x,
            session.current_z,
            end_height,
            max(editor.radius * .35, f32(4)),
            max(editor.radius * .25, f32(4)),
            amount,
        )
    case .Terrace:
        gesture_amount := clamp(abs(session.displacement) / max(editor.radius * .25, f32(1)), f32(0), f32(1)) * amount
        if editor.terrain_sculpt.area {
            return terrain.apply_terrace_area_operator(
                &editor.project,
                terrain_sculpt_area_geometry(editor, session),
                5,
                editor.project.sea_level,
                gesture_amount,
                editor.hardness,
            )
        }
        return terrain.apply_terrace_operator(
            &editor.project,
            session.owner,
            session.start_x,
            session.start_z,
            editor.radius,
            5,
            editor.project.sea_level,
            gesture_amount,
            editor.hardness,
        )
    case .Erode:
        gesture_amount := clamp(abs(session.displacement) / max(editor.radius * .25, f32(1)), f32(0), f32(1)) * amount
        talus := max(editor.project.levels[0].cell_size * .08, f32(.1))
        if editor.terrain_sculpt.area {
            return terrain.apply_erode_area_operator(
                &editor.project,
                terrain_sculpt_area_geometry(editor, session),
                talus,
                gesture_amount,
                editor.hardness,
            )
        }
        return terrain.apply_erode_operator(
            &editor.project,
            session.owner,
            session.start_x,
            session.start_z,
            editor.radius,
            talus,
            gesture_amount,
            editor.hardness,
        )
    }
    return false
}

terrain_sculpt_begin :: proc(editor: ^Editor, world_x, world_z: f32) {
    if editor == nil do return
    owner := terrain.island_at(&editor.project, world_x, world_z)
    if owner == .World do return
    mouse := canvas2d.GetMousePosition()
    editor.terrain_sculpt.session = {
        active         = true,
        valid          = true,
        owner          = owner,
        start_x        = world_x,
        start_z        = world_z,
        current_x      = world_x,
        current_z      = world_z,
        start_screen_y = mouse.y,
        sampled_height = terrain.sample_surface_height(&editor.project, 0, world_x, world_z),
        dirty_x        = world_x,
        dirty_z        = world_z,
        dirty_radius   = editor.radius,
        base           = new(Terrain_History_State),
    }
    if editor.terrain_sculpt.session.base == nil {
        editor.terrain_sculpt.session = {}
        terrain_file_feedback(editor, "NOT ENOUGH MEMORY")
        return
    }
    terrain_history_capture(editor, editor.terrain_sculpt.session.base)
}

terrain_sculpt_update_preview :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    session := &editor.terrain_sculpt.session
    if editor == nil || !session.active do return
    if cursor_hit {
        session.current_x, session.current_z = world_x, world_z
        session.valid = terrain.island_at(&editor.project, world_x, world_z) == session.owner
    }
    mouse := canvas2d.GetMousePosition()
    metres_per_pixel := clamp(editor.camera_pose.position.y / 1200, f32(.08), f32(.8))
    session.displacement = (session.start_screen_y - mouse.y) * metres_per_pixel
    dx, dz := session.current_x - session.start_x, session.current_z - session.start_z
    session.dirty_x, session.dirty_z =
        (session.start_x + session.current_x) * .5, (session.start_z + session.current_z) * .5
    session.dirty_radius = editor.radius
    if editor.terrain_sculpt.mode == .Grade || editor.terrain_sculpt.area {
        session.dirty_radius = f32(math.sqrt(f64(dx * dx + dz * dz))) * .5 + editor.radius
    }
    terrain_sculpt_restore_base(editor)
    session.changed = terrain_sculpt_apply(editor, session)
    world_terrain_changed(editor, session.dirty_x, session.dirty_z, session.dirty_radius)
}

terrain_sculpt_cancel :: proc(editor: ^Editor) {
    if editor == nil || !editor.terrain_sculpt.session.active do return
    session := &editor.terrain_sculpt.session
    dirty_x, dirty_z, dirty_radius := session.dirty_x, session.dirty_z, session.dirty_radius
    terrain_sculpt_restore_base(editor)
    terrain_sculpt_reseat_structures(editor, dirty_x, dirty_z, dirty_radius)
    world_terrain_changed(editor, dirty_x, dirty_z, dirty_radius)
    free(session.base)
    editor.terrain_sculpt.session = {}
}

terrain_sculpt_commit :: proc(editor: ^Editor) {
    if editor == nil || !editor.terrain_sculpt.session.active do return
    session := &editor.terrain_sculpt.session
    meaningful := session.valid && session.changed
    switch editor.terrain_sculpt.mode {
    case .Level, .Terrace, .Erode:
        meaningful = meaningful && abs(session.displacement) > .001
        if editor.terrain_sculpt.area {
            meaningful =
                meaningful &&
                abs(session.current_x - session.start_x) > .01 &&
                abs(session.current_z - session.start_z) > .01
        }
    case .Grade:
        dx, dz := session.current_x - session.start_x, session.current_z - session.start_z
        meaningful = meaningful && dx * dx + dz * dz > .0001
    case .Shape:
        meaningful = false
    }
    dirty_x, dirty_z, dirty_radius := session.dirty_x, session.dirty_z, session.dirty_radius
    terrain_sculpt_restore_base(editor)
    if !meaningful {
        world_terrain_changed(editor, dirty_x, dirty_z, dirty_radius)
        free(session.base)
        editor.terrain_sculpt.session = {}
        return
    }
    terrain_history_push_undo(editor)
    free(session.base)
    session.base = nil
    if !terrain_sculpt_apply(editor, session) {
        editor.terrain_undo_count -= 1
        editor.terrain_sculpt.session = {}
        return
    }
    _ = terrain.bathymetry_refresh_generated_bounds(
        &editor.project,
        dirty_x - dirty_radius,
        dirty_z - dirty_radius,
        dirty_x + dirty_radius,
        dirty_z + dirty_radius,
    )
    terrain.terrain_pages_rebuild(&editor.project)
    terrain_sculpt_reseat_structures(editor, dirty_x, dirty_z, dirty_radius)
    world_terrain_changed(editor, dirty_x, dirty_z, dirty_radius)
    editor.terrain_sculpt.session = {}
}

terrain_sculpt_destroy :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.terrain_sculpt.session.base != nil do free(editor.terrain_sculpt.session.base)
    editor.terrain_sculpt.session = {}
}

terrain_sculpt_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) -> bool {
    if !terrain_sculpt_owns_direct_brush(editor) do return false
    session := &editor.terrain_sculpt.session
    if !session.active {
        if cursor_hit && canvas2d.IsMouseButtonPressed(.LEFT) do terrain_sculpt_begin(editor, world_x, world_z)
        return session.active
    }
    if canvas2d.IsMouseButtonDown(.LEFT) {
        terrain_sculpt_update_preview(editor, world_x, world_z, cursor_hit)
        return true
    }
    if canvas2d.IsMouseButtonReleased(.LEFT) {
        terrain_sculpt_commit(editor)
        return true
    }
    return true
}
