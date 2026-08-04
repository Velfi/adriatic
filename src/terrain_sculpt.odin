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

Terrain_Family :: enum u8 {
    Landmass,
    Primary_Forms,
    Surface,
    Built_Terrain,
}
Terrain_Action :: enum u8 {
    Coast,
    Shelf,
    Ridge,
    Valley,
    Slope,
    Grade,
    Relax,
    Erode,
    Deposit,
    Roughen,
    Terrace,
    Pad,
    Cut_Fill,
}
Terrain_Elevation_Mode :: enum u8 {
    Sampled,
    Explicit,
}
Terrain_Authoring_Target :: enum u8 {
    Terrain,
    Land,
    Bathymetry,
}
TERRAIN_SCULPT_PATH_CAPACITY :: 256

Terrain_Authoring_Settings :: struct {
    size:                  f32,
    feather:               f32,
    flow:                  f32,
    brush_strength:        f32,
    spacing:               f32,
    inner_core:            f32,
    affect_seabed:         bool,
    direction:             f32,
    beach_elevation:       f32,
    shelf_depth:           f32,
    shelf_slope:           f32,
    height:                f32,
    profile:               terrain.Authoring_Profile,
    side_bias:             f32,
    roughness:             f32,
    endpoint_taper:        f32,
    maximum_grade:         f32,
    grade_start_elevation: f32,
    grade_end_elevation:   f32,
    preserve_detail:       f32,
    iterations:            int,
    talus:                 f32,
    rainfall:              f32,
    sediment:              f32,
    preserve_coastline:    bool,
    amplitude:             f32,
    noise_scale:           f32,
    octaves:               int,
    seed:                  u32,
    terrace_height:        f32,
    terrace_depth:         f32,
    terrace_reference:     f32,
    retaining_slope:       f32,
    irregularity:          f32,
    elevation_mode:        Terrain_Elevation_Mode,
    target_elevation:      f32,
    edge_slope:            f32,
    corner_radius:         f32,
    cut_limit:             f32,
    fill_limit:            f32,
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
    path:                           [TERRAIN_SCULPT_PATH_CAPACITY]terrain.Cliff_Point,
    path_count:                     int,
    applied_path_count:             int,
    start_height, end_height:       f32,
    grade_valid:                    bool,
    effective_resolution:           f32,
    finalizing:                     bool,
    cut_volume, fill_volume:        f32,
}

Terrain_Sculpt_State :: struct {
    // mode and area decode old fixtures and are not used by the live workspace.
    mode:     Terrain_Sculpt_Mode,
    area:     bool,
    family:   Terrain_Family,
    action:   Terrain_Action,
    settings: [13]Terrain_Authoring_Settings,
    advanced: bool,
    session:  Terrain_Sculpt_Session,
}

terrain_action_is_spline :: #force_inline proc(action: Terrain_Action) -> bool {
    return action == .Ridge || action == .Valley || action == .Slope || action == .Grade
}

terrain_action_is_area :: #force_inline proc(action: Terrain_Action) -> bool {
    return action == .Pad
}

terrain_action_target :: #force_inline proc(action: Terrain_Action) -> Terrain_Authoring_Target {
    if action == .Coast do return .Land
    if action == .Shelf do return .Bathymetry
    return .Terrain
}

terrain_action_seabed_policy_editable :: #force_inline proc(action: Terrain_Action) -> bool {
    return terrain_action_target(action) == .Terrain
}

terrain_action_affects_seabed :: #force_inline proc(action: Terrain_Action, configured: bool) -> bool {
    return terrain_action_target(action) != .Terrain || configured
}

terrain_authoring_defaults :: proc(state: ^Terrain_Sculpt_State, sea_level: f32) {
    if state == nil do return
    state.family, state.action = .Landmass, .Coast
    for &settings in state.settings {
        settings = {
            size               = 120,
            feather            = 36,
            flow               = .65,
            brush_strength     = .10,
            spacing            = .2,
            inner_core         = .55,
            direction          = 1,
            beach_elevation    = 2,
            shelf_depth        = -12,
            shelf_slope        = 1.4,
            height             = 24,
            profile            = .Round,
            endpoint_taper     = .12,
            maximum_grade      = .12,
            iterations         = 24,
            talus              = .15,
            rainfall           = .5,
            sediment           = .5,
            preserve_coastline = true,
            amplitude          = 4,
            noise_scale        = 48,
            octaves            = 3,
            terrace_height     = 5,
            terrace_depth      = 12,
            terrace_reference  = sea_level,
            retaining_slope    = .75,
            target_elevation   = sea_level + 4,
            edge_slope         = .5,
            corner_radius      = 4,
            cut_limit          = 30,
            fill_limit         = 30,
        }
    }
    state.settings[int(Terrain_Action.Coast)].affect_seabed = true
    state.settings[int(Terrain_Action.Shelf)].affect_seabed = true
    state.settings[int(Terrain_Action.Relax)].size = 64
    state.settings[int(Terrain_Action.Erode)].size = 100
    state.settings[int(Terrain_Action.Terrace)].size = 90
}

terrain_authoring_select :: proc(editor: ^Editor, family: Terrain_Family, action: Terrain_Action) {
    if editor == nil do return
    if editor.terrain_sculpt.session.active do terrain_sculpt_cancel(editor)
    editor.authoring_tool = .Sculpt
    editor.tool = .Raise
    editor.terrain_sculpt.family = family
    editor.terrain_sculpt.action = action
}

terrain_authoring_normalize_legacy_selection :: proc(editor: ^Editor) {
    if editor == nil do return
    legacy := editor.authoring_tool
    terrain_authoring_defaults(&editor.terrain_sculpt, editor.project.sea_level)
    #partial switch legacy {
    case .Smooth:
        editor.authoring_tool = .Sculpt; editor.tool = .Raise
        editor.terrain_sculpt.family = .Surface; editor.terrain_sculpt.action = .Relax
    case .Ridge:
        editor.authoring_tool = .Sculpt; editor.tool = .Raise
        editor.terrain_sculpt.family = .Primary_Forms; editor.terrain_sculpt.action = .Ridge
    case .Cliff:
        editor.authoring_tool = .Sculpt; editor.tool = .Raise
        editor.terrain_sculpt.family = .Primary_Forms; editor.terrain_sculpt.action = .Ridge
        editor.terrain_sculpt.settings[int(Terrain_Action.Ridge)].profile = .Cliff
    case:
    }
}

terrain_sculpt_owns_direct_brush :: #force_inline proc(editor: ^Editor) -> bool {
    return editor != nil && editor.authoring_tool == .Sculpt
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
        boundary_blend = max(editor.terrain_sculpt.settings[int(editor.terrain_sculpt.action)].feather, f32(2)),
    }
}

terrain_sculpt_apply :: proc(editor: ^Editor, session: ^Terrain_Sculpt_Session) -> bool {
    if editor == nil || session == nil || !session.active || !session.valid do return false
    action := editor.terrain_sculpt.action
    settings := editor.terrain_sculpt.settings[int(action)]
    affects_seabed := terrain_action_affects_seabed(action, settings.affect_seabed)
    if terrain_action_is_spline(action) {
        operation := terrain.Authoring_Spline_Operation.Ridge
        #partial switch action {
        case .Ridge:
            operation = .Ridge
        case .Valley:
            operation = .Valley
        case .Slope:
            operation = .Slope
        case .Grade:
            operation = .Grade
        case:
            return false
        }
        session.grade_valid = true
        if action == .Grade {
            length := f32(0)
            for index in 0 ..< session.path_count - 1 {
                dx := session.path[index + 1].x - session.path[index].x
                dz := session.path[index + 1].z - session.path[index].z
                length += f32(math.sqrt(f64(dx * dx + dz * dz)))
            }
            session.grade_valid =
                settings.maximum_grade <= 0 ||
                abs(session.end_height - session.start_height) / max(length, f32(.001)) <= settings.maximum_grade
            if !session.grade_valid do return false
        }
        return terrain.apply_authoring_spline(
            &editor.project,
            {
                owner = session.owner,
                operation = operation,
                points = session.path[:session.path_count],
                width = settings.size,
                feather = settings.feather,
                flow = settings.flow,
                height = settings.height,
                side_bias = settings.side_bias,
                roughness = settings.roughness,
                endpoint_taper = settings.endpoint_taper,
                start_height = session.start_height,
                end_height = session.end_height,
                maximum_grade = settings.maximum_grade,
                preserve_detail = settings.preserve_detail,
                affect_seabed = affects_seabed,
                profile = settings.profile,
                seed = settings.seed,
            },
        )
    }
    if action == .Pad {
        changed, volume := terrain.apply_authoring_area(
            &editor.project,
            {
                owner = session.owner,
                start_x = session.start_x,
                start_z = session.start_z,
                end_x = session.current_x,
                end_z = session.current_z,
                target_height = settings.elevation_mode == .Sampled ? session.sampled_height : settings.target_elevation,
                feather = max(settings.edge_slope * settings.size, settings.feather),
                flow = settings.flow,
                corner_radius = settings.corner_radius,
                affect_seabed = affects_seabed,
                cut_limit = settings.cut_limit,
                fill_limit = settings.fill_limit,
            },
        )
        session.cut_volume, session.fill_volume = volume.cut, volume.fill
        return changed
    }
    operation := terrain.Authoring_Brush_Operation.Coast
    #partial switch action {
    case .Coast:
        operation = .Coast
    case .Shelf:
        operation = .Shelf
    case .Relax:
        operation = .Relax
    case .Erode:
        operation = .Erode
    case .Deposit:
        operation = .Deposit
    case .Roughen:
        operation = .Roughen
    case .Terrace:
        operation = .Terrace
    case .Cut_Fill:
        operation = .Cut_Fill
    case:
        return false
    }
    first_point := 0
    if !session.finalizing {
        first_point = session.applied_path_count
        if first_point >= session.path_count do first_point = session.path_count - 1
    }
    changed := false
    for point in session.path[first_point:session.path_count] {
        changed =
            terrain.apply_authoring_brush(
                &editor.project,
                {
                    owner = session.owner,
                    operation = operation,
                    world_x = point.x,
                    world_z = point.z,
                    size = settings.size,
                    inner_core = settings.inner_core,
                    feather = settings.feather,
                    // Flow defines the authored brush profile. Strength makes a
                    // held stroke deliberate instead of reapplying a full flow
                    // value on every rendered frame.
                    flow = settings.flow * settings.brush_strength,
                    direction = settings.direction,
                    affect_seabed = affects_seabed,
                    target_height = settings.elevation_mode == .Sampled ? session.sampled_height : settings.target_elevation,
                    beach_height = settings.beach_elevation,
                    shelf_depth = settings.shelf_depth,
                    shelf_slope = settings.shelf_slope,
                    talus = settings.talus,
                    iterations = settings.iterations,
                    rainfall = settings.rainfall,
                    sediment_capacity = settings.sediment,
                    amplitude = settings.amplitude,
                    noise_scale = settings.noise_scale,
                    octaves = settings.octaves,
                    seed = settings.seed,
                    terrace_height = settings.terrace_height,
                    terrace_reference = settings.terrace_reference,
                    terrace_depth = settings.terrace_depth,
                    retaining_slope = settings.retaining_slope,
                    irregularity = settings.irregularity,
                    cut_limit = settings.cut_limit,
                    fill_limit = settings.fill_limit,
                    preserve_coastline = settings.preserve_coastline,
                    quality = session.finalizing ? .Final : .Interactive,
                },
            ) ||
            changed
    }
    if !session.finalizing do session.applied_path_count = session.path_count
    return changed
}

terrain_sculpt_begin :: proc(editor: ^Editor, world_x, world_z: f32) {
    if editor == nil do return
    owner := terrain.island_at(&editor.project, world_x, world_z)
    if owner == .World do return
    mouse := canvas2d.GetMousePosition()
    settings := &editor.terrain_sculpt.settings[int(editor.terrain_sculpt.action)]
    if canvas2d.IsMouseButtonPressed(.RIGHT) && editor.terrain_sculpt.action == .Coast do settings.direction = -1
    if canvas2d.IsMouseButtonPressed(.LEFT) && editor.terrain_sculpt.action == .Coast do settings.direction = 1
    sampled := terrain.sample_surface_height(&editor.project, 0, world_x, world_z)
    editor.terrain_sculpt.session = {
        active               = true,
        valid                = true,
        owner                = owner,
        start_x              = world_x,
        start_z              = world_z,
        current_x            = world_x,
        current_z            = world_z,
        start_screen_y       = mouse.y,
        sampled_height       = sampled,
        dirty_x              = world_x,
        dirty_z              = world_z,
        dirty_radius         = settings.size + settings.feather,
        base                 = new(Terrain_History_State),
        path_count           = 1,
        start_height         = sampled,
        end_height           = sampled,
        grade_valid          = true,
        effective_resolution = terrain.FINE_CELL_SIZE,
    }
    editor.terrain_sculpt.session.path[0] = {world_x, world_z}
    if editor.terrain_sculpt.action == .Grade && settings.elevation_mode == .Explicit {
        editor.terrain_sculpt.session.start_height = settings.grade_start_elevation
        editor.terrain_sculpt.session.end_height = settings.grade_end_elevation
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
    settings := editor.terrain_sculpt.settings[int(editor.terrain_sculpt.action)]
    drag_preview := terrain_action_is_spline(editor.terrain_sculpt.action) || terrain_action_is_area(editor.terrain_sculpt.action)
    // Spline and area tools are position-defined previews. Brush tools are
    // hold-defined and must build on their preceding held stamp.
    if drag_preview do terrain_sculpt_restore_base(editor)
    if cursor_hit {
        session.current_x, session.current_z = world_x, world_z
        session.valid = terrain.island_at(&editor.project, world_x, world_z) == session.owner
        if session.valid && session.path_count < TERRAIN_SCULPT_PATH_CAPACITY {
            last := session.path[session.path_count - 1]
            dx, dz := world_x - last.x, world_z - last.z
            step := max(settings.size * max(settings.spacing, f32(.05)), editor.project.levels[0].cell_size * .5)
            distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
            if terrain_action_is_spline(editor.terrain_sculpt.action) {
                step = max(editor.project.levels[0].cell_size, settings.size * .08)
            }
            stamps := int(math.floor(f64(distance / step)))
            if stamps > 0 {
                nx, nz := dx / distance, dz / distance
                for stamp in 1 ..= min(stamps, TERRAIN_SCULPT_PATH_CAPACITY - session.path_count) {
                    travel := f32(stamp) * step
                    session.path[session.path_count] = {last.x + nx * travel, last.z + nz * travel}
                    session.path_count += 1
                }
            }
        }
        if editor.terrain_sculpt.action != .Grade || settings.elevation_mode == .Sampled {
            session.end_height = terrain.sample_surface_height(&editor.project, 0, world_x, world_z)
        }
    }
    mouse := canvas2d.GetMousePosition()
    metres_per_pixel := clamp(editor.camera_pose.position.y / 1200, f32(.08), f32(.8))
    session.displacement = (session.start_screen_y - mouse.y) * metres_per_pixel
    dx, dz := session.current_x - session.start_x, session.current_z - session.start_z
    session.dirty_x, session.dirty_z =
        (session.start_x + session.current_x) * .5, (session.start_z + session.current_z) * .5
    session.dirty_radius = settings.size + settings.feather
    source_x, source_z := terrain.island_source_position(&editor.project, session.current_x, session.current_z)
    authored_level := terrain.terrain_operator_authored_level(
        &editor.project,
        source_x - settings.size - settings.feather,
        source_z - settings.size - settings.feather,
        source_x + settings.size + settings.feather,
        source_z + settings.size + settings.feather,
    )
    session.effective_resolution = editor.project.levels[authored_level].cell_size
    if terrain_action_is_spline(editor.terrain_sculpt.action) || terrain_action_is_area(editor.terrain_sculpt.action) {
        session.dirty_radius = f32(math.sqrt(f64(dx * dx + dz * dz))) * .5 + settings.size + settings.feather
    }
    session.changed = terrain_sculpt_apply(editor, session) || session.changed
    world_terrain_changed(editor, session.dirty_x, session.dirty_z, session.dirty_radius, true)
    // A spline preview's final dirty bounds can cover the full drag. Keep the
    // live renderer focused on the current tip so it can show immediate
    // feedback without regenerating that whole accumulated span every frame.
    preview_radius := settings.size + settings.feather
    world_renderer.terrain_live_edit_frame_dirty = {
        valid    = true,
        revision = editor.terrain_revision,
        min_x    = session.current_x - preview_radius,
        min_z    = session.current_z - preview_radius,
        max_x    = session.current_x + preview_radius,
        max_z    = session.current_z + preview_radius,
    }
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
    meaningful := session.valid && session.changed && session.grade_valid
    if terrain_action_is_spline(editor.terrain_sculpt.action) {
        meaningful = meaningful && session.path_count >= 2
    } else if terrain_action_is_area(editor.terrain_sculpt.action) {
        meaningful =
            meaningful &&
            abs(session.current_x - session.start_x) > .01 &&
            abs(session.current_z - session.start_z) > .01
    }
    dirty_x, dirty_z, dirty_radius := session.dirty_x, session.dirty_z, session.dirty_radius
    incremental_brush := !terrain_action_is_spline(editor.terrain_sculpt.action) && !terrain_action_is_area(editor.terrain_sculpt.action)
    if !incremental_brush do terrain_sculpt_restore_base(editor)
    if !meaningful {
        if incremental_brush do terrain_sculpt_restore_base(editor)
        world_terrain_changed(editor, dirty_x, dirty_z, dirty_radius)
        free(session.base)
        editor.terrain_sculpt.session = {}
        return
    }
    if incremental_brush {
        final := new(Terrain_History_State)
        if final == nil {
            terrain_sculpt_cancel(editor)
            terrain_file_feedback(editor, "NOT ENOUGH MEMORY")
            return
        }
        terrain_history_capture(editor, final)
        terrain_sculpt_restore_base(editor)
        terrain_history_push_undo(editor)
        terrain_history_restore(editor, final)
        free(final)
    } else {
        terrain_history_push_undo(editor)
    }
    free(session.base)
    session.base = nil
    if !incremental_brush {
        session.finalizing = true
        if !terrain_sculpt_apply(editor, session) {
            editor.terrain_undo_count -= 1
            editor.terrain_sculpt.session = {}
            return
        }
    }
    _ = terrain.bathymetry_refresh_generated_bounds(
        &editor.project,
        dirty_x - dirty_radius,
        dirty_z - dirty_radius,
        dirty_x + dirty_radius,
        dirty_z + dirty_radius,
    )
    marine_habitat_rebuild_world(editor)
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
        if cursor_hit && (canvas2d.IsMouseButtonPressed(.LEFT) || canvas2d.IsMouseButtonPressed(.RIGHT)) do terrain_sculpt_begin(editor, world_x, world_z)
        return session.active
    }
    if canvas2d.IsMouseButtonDown(.LEFT) || canvas2d.IsMouseButtonDown(.RIGHT) {
        terrain_sculpt_update_preview(editor, world_x, world_z, cursor_hit)
        return true
    }
    if canvas2d.IsMouseButtonReleased(.LEFT) || canvas2d.IsMouseButtonReleased(.RIGHT) {
        terrain_sculpt_commit(editor)
        return true
    }
    return true
}
