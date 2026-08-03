package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import farmland "../packages/farmland"
import road_designer "../packages/road_designer"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:c"
import "core:fmt"
import "core:math"
import "core:sync"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"

Authoring_Tool :: enum {
    Sculpt,
    Smooth,
    Paint,
    Formations,
    Foliage,
    Ridge,
    Cliff,
    Building,
    Marina,
    Farm,
    Wreck,
    ClimbingLeaves,
    Roads,
    GreekAssets,
    Obstacles,
}

Plant_Stamp_Mode :: enum u8 {
    Ground,
    Climbing,
}

// GreekAssets remains as a frozen enum value for historical Fixture decoding,
// but is no longer part of the live editor tool palette.
AUTHORING_TOOL_COUNT :: 14
AUTHORING_TOOL_DISPLAY_COUNT :: AUTHORING_TOOL_COUNT - 4
AUTHORING_TOOL_PALETTE_COUNT :: AUTHORING_TOOL_DISPLAY_COUNT + 2
AUTHORING_TOOL_DISPLAY_ORDER := [AUTHORING_TOOL_DISPLAY_COUNT]Authoring_Tool {
    .Sculpt,
    .Paint,
    .Roads,
    .Formations,
    .Foliage,
    .Building,
    .Farm,
    .Marina,
    .Wreck,
    .Obstacles,
}
EDITOR_UI_TOP_HEIGHT :: f32(54)
EDITOR_UI_RAIL_WIDTH :: f32(184)
EDITOR_UI_INSPECTOR_WIDTH :: f32(292)
EDITOR_UI_GUTTER :: f32(12)
EDITOR_UI_BUTTON_TEXT_Y_OFFSET :: f32(3)
EDITOR_UI_TOOL_COLUMNS :: 3
EDITOR_UI_TOOL_BUTTON_SIZE :: f32(48)
EDITOR_UI_TOOL_BUTTON_GAP :: f32(6)

FIXTURE_FILE_PATH_CAPACITY :: 1024

Fixture_File_Dialog_Mode :: enum {
    Closed,
    Save,
    Load,
}

Fixture_File_Dialog_State :: struct {
    finished:    u32,
    pending:     bool,
    mode:        Fixture_File_Dialog_Mode,
    path:        [FIXTURE_FILE_PATH_CAPACITY]u8,
    path_length: int,
}

FIXTURE_FILE_FILTERS: [1]sdl.DialogFileFilter = {{"Fixture", "fixture"}}

Editor_UI_State :: struct {
    left_collapsed:      bool,
    inspector_collapsed: bool,
    active_slider:       int `fixture:"-"`,
    debug_key_down:      bool `fixture:"-"`,
}

Editor_UI_Layout :: struct {
    top:               canvas2d.Rectangle,
    left:              canvas2d.Rectangle,
    inspector:         canvas2d.Rectangle,
    hint:              canvas2d.Rectangle,
    left_toggle:       canvas2d.Rectangle,
    inspector_toggle:  canvas2d.Rectangle,
    left_visible:      bool,
    inspector_visible: bool,
}

@(no_instrumentation)
authoring_tool_name :: #force_inline proc(tool: Authoring_Tool) -> cstring {
    switch tool {
    case .Sculpt:
        return "SCULPT"
    case .Smooth:
        return "SMOOTH"
    case .Paint:
        return "PAINT"
    case .Formations:
        return "FORMATIONS"
    case .Foliage:
        return "PLANT STAMP"
    case .Ridge:
        return "RIDGE"
    case .Cliff:
        return "CLIFF"
    case .Building:
        return "CITY BRUSH"
    case .Marina:
        return "MARINA STAMP"
    case .Farm:
        return "FARM STAMP"
    case .Wreck:
        return "WRECK STAMP"
    case .ClimbingLeaves:
        return "PLANT STAMP"
    case .Roads:
        return "ROADS"
    case .GreekAssets:
        return "RUIN STAMP"
    case .Obstacles:
        return "OBSTACLES"
    }
    return "TOOL"
}

terrain_family_name :: #force_inline proc(family: Terrain_Family) -> cstring {
    switch family {case .Landmass:
        return "LANDMASS"; case .Primary_Forms:
        return "FORMS"; case .Surface:
        return "SURFACE"; case .Built_Terrain:
        return "BUILT"}
    return "TERRAIN"
}

terrain_action_name :: #force_inline proc(action: Terrain_Action) -> cstring {
    switch action {
    case .Coast:
        return "COAST"
    case .Shelf:
        return "SHELF"
    case .Ridge:
        return "RIDGE"
    case .Valley:
        return "VALLEY"
    case .Slope:
        return "SLOPE"
    case .Grade:
        return "GRADE"
    case .Relax:
        return "RELAX"
    case .Erode:
        return "ERODE"
    case .Deposit:
        return "DEPOSIT"
    case .Roughen:
        return "ROUGHEN"
    case .Terrace:
        return "TERRACE"
    case .Pad:
        return "PAD"
    case .Cut_Fill:
        return "CUT/FILL"
    }
    return "TERRAIN"
}

terrain_family_actions :: proc(family: Terrain_Family) -> ([4]Terrain_Action, int) {
    switch family {
    case .Landmass:
        return {.Coast, .Shelf, .Shelf, .Shelf}, 2
    case .Primary_Forms:
        return {.Ridge, .Valley, .Slope, .Grade}, 4
    case .Surface:
        return {.Relax, .Erode, .Deposit, .Roughen}, 4
    case .Built_Terrain:
        return {.Terrace, .Pad, .Cut_Fill, .Cut_Fill}, 3
    }
    return {}, 0
}

@(no_instrumentation)
authoring_tool_shortcut :: #force_inline proc(tool: Authoring_Tool) -> cstring {
    switch tool {
    case .Sculpt:
        return ""
    case .Smooth:
        return ""
    case .Paint:
        return "T"
    case .Formations:
        return "B"
    case .Foliage:
        return "H"
    case .Ridge:
        return "Z"
    case .Cliff:
        return "C"
    case .Building:
        return "N"
    case .Marina:
        return "J"
    case .Farm:
        return "K"
    case .Wreck:
        return "V"
    case .ClimbingLeaves:
        return "L"
    case .Roads:
        return "M"
    case .GreekAssets:
        return "G"
    case .Obstacles:
        return ""
    }
    return ""
}

authoring_select_tool :: proc(editor: ^Editor, selected: Authoring_Tool) {
    if editor == nil do return
    if editor.terrain_sculpt.session.active do terrain_sculpt_cancel(editor)
    // ClimbingLeaves is retained only as a frozen Fixture enum value. Route
    // legacy selection and the old L shortcut into the unified plant stamp.
    resolved := selected
    if selected == .ClimbingLeaves {
        resolved = .Foliage
        editor.plant_stamp_mode = .Climbing
    }
    editor.authoring_tool = resolved
    editor.selection_tool_active = false
    editor.architecture_painting = false
    architecture.city_plan_destroy(&editor.architecture_preview_plan)
    editor.architecture_dirty_bounds = {}
    editor.architecture_node_mode = false
    editor.architecture_paint_mode = false
    editor.airport_stamp_mode = false
    editor.airport_preview_valid = false
    editor.marina_paint_mode = false
    editor.marina_preview_valid = false
    editor.farm_paint_mode = false
    editor.wreck_paint_mode = false
    editor.climbing_leaf_paint_mode = false
    editor.climbing_leaf_painting = false
    editor.plant_stamp_target_valid = false
    editor.plant_stamp_target_index = -1
    editor.formation_brush_painting = false
    editor.formation_brush_group_id = 0
    editor.rock_placement_mode = false
    editor.greek_placement_mode = false
    editor.road_mode = false
    editor.curve_mode = false
    switch resolved {
    case .Sculpt:
        editor.tool = .Raise
    case .Smooth:
        editor.authoring_tool = .Sculpt
        editor.tool = .Raise
        editor.terrain_sculpt.family = .Surface
        editor.terrain_sculpt.action = .Relax
    case .Paint:
        editor.tool = .Paint
    case .Formations:
        editor.tool = .Structure
    case .Foliage:
        editor.tool = .Structure
        editor.climbing_leaf_paint_mode = editor.plant_stamp_mode == .Climbing
    case .Ridge:
        editor.authoring_tool = .Sculpt
        editor.tool = .Raise
        editor.terrain_sculpt.family = .Primary_Forms
        editor.terrain_sculpt.action = .Ridge
        editor.terrain_sculpt.settings[int(Terrain_Action.Ridge)].profile = .Round
    case .Cliff:
        editor.authoring_tool = .Sculpt
        editor.tool = .Raise
        editor.terrain_sculpt.family = .Primary_Forms
        editor.terrain_sculpt.action = .Ridge
        editor.terrain_sculpt.settings[int(Terrain_Action.Ridge)].profile = .Cliff
    case .Building:
        editor.tool = .Structure
        editor.architecture_paint_mode = true
    case .Marina:
        editor.tool = .Structure
        editor.marina_paint_mode = true
        // A previous placement or rejected site leaves the preview invalid.
        // Reset the state so reselecting the stamp immediately evaluates the
        // shoreline under the cursor instead of waiting for a large cursor move.
        editor.marina_brush_status = .Idle
    case .Farm:
        editor.tool = .Structure
        editor.farm_paint_mode = true
    case .Wreck:
        editor.tool = .Structure
        editor.wreck_paint_mode = true
    case .ClimbingLeaves:
    case .Roads:
        editor.tool = .Structure
        editor.road_mode = true
        editor.structure_selected = -1
    case .GreekAssets:
        editor.tool = .Structure
        editor.greek_placement_mode = true
        editor.structure_selected = -1
    case .Obstacles:
        editor.tool = .Structure
    }
    editor.tweak.terrain.tool = editor.tool
    curve_reset(editor)
    editor.structure_placing = false
    editor.structure_moving = false
}

authoring_select_selection_tool :: proc(editor: ^Editor) {
    if editor == nil do return
    // Reuse the common cancellation path, then turn the structure interaction
    // into selection-only behavior. This mode is session state, not map data.
    authoring_select_tool(editor, .Formations)
    editor.selection_tool_active = true
    editor.tool = .Structure
    editor.tweak.terrain.tool = editor.tool
}

authoring_select_rock_tool :: proc(editor: ^Editor) {
    if editor == nil do return
    authoring_select_tool(editor, .Formations)
    editor.rock_placement_mode = true
    editor.structure_auto_kind = false
    editor.structure_kind = .Rock
}

fixture_file_path_copy :: proc(destination: []u8, source: string) -> int {
    count := min(len(destination), len(source))
    if count > 0 do copy(destination[:count], transmute([]u8)source[:count])
    return count
}

fixture_editor_current_path :: proc(editor: ^Editor) -> string {
    if editor == nil || editor.fixture_path_length <= 0 do return ""
    return string(editor.fixture_path[:editor.fixture_path_length])
}

fixture_editor_set_path :: proc(editor: ^Editor, path: string) {
    if editor == nil do return
    editor.fixture_path = {}
    editor.fixture_path_length = fixture_file_path_copy(editor.fixture_path[:], path)
}

fixture_editor_file_dialog_is_open :: proc(editor: ^Editor) -> bool {
    return editor != nil && editor.fixture_file_dialog.pending
}

fixture_editor_file_dialog_close :: proc(editor: ^Editor) {
    if editor == nil do return
    if !editor.fixture_file_dialog.pending do return
    editor.fixture_file_dialog = {}
}

fixture_file_dialog_callback :: proc "c" (userdata: rawptr, filelist: [^]cstring, _filter: c.int) {
    dialog := cast(^Fixture_File_Dialog_State)userdata
    if dialog == nil do return
    dialog.path_length = 0
    if filelist != nil && filelist[0] != nil {
        selected := string(filelist[0])
        dialog.path_length = min(len(selected), FIXTURE_FILE_PATH_CAPACITY - 1)
        if dialog.path_length > 0 {
            copy(dialog.path[:dialog.path_length], transmute([]u8)selected[:dialog.path_length])
        }
    }
    sync.atomic_store_explicit(&dialog.finished, u32(1), .Release)
}

fixture_file_dialog_default_location :: proc(editor: ^Editor) -> cstring {
    if editor == nil do return ""
    current_path := fixture_editor_current_path(editor)
    if current_path != "" do return fmt.ctprintf("%s", current_path)

    default_path, path_error, path_ok := fixture_editor_store_default_path(context.temp_allocator)
    defer fixture_editor_store_error_dispose(&path_error)
    if !path_ok do return ""
    defer delete(default_path, context.temp_allocator)
    return fmt.ctprintf("%s", default_path)
}

fixture_editor_file_dialog_open :: proc(editor: ^Editor, mode: Fixture_File_Dialog_Mode) {
    if editor == nil || fixture_editor_file_dialog_is_open(editor) do return
    state := &editor.fixture_file_dialog
    state^ = {
        pending = true,
        mode    = mode,
    }
    sync.atomic_store_explicit(&state.finished, u32(0), .Release)

    window := sdl.GetKeyboardFocus()
    filters := raw_data(FIXTURE_FILE_FILTERS[:])
    default_location := fixture_file_dialog_default_location(editor)
    if mode == .Save {
        sdl.ShowSaveFileDialog(
            fixture_file_dialog_callback,
            state,
            window,
            filters,
            c.int(len(FIXTURE_FILE_FILTERS)),
            default_location,
        )
    } else {
        sdl.ShowOpenFileDialog(
            fixture_file_dialog_callback,
            state,
            window,
            filters,
            c.int(len(FIXTURE_FILE_FILTERS)),
            default_location,
            false,
        )
    }
}

fixture_file_dialog_poll :: proc(editor: ^Editor) {
    if editor == nil || !fixture_editor_file_dialog_is_open(editor) do return
    state := &editor.fixture_file_dialog
    if sync.atomic_load_explicit(&state.finished, .Acquire) == 0 do return

    path := string(state.path[:state.path_length])
    if path == "" {
        terrain_file_feedback(editor, "FIXTURE CANCELLED")
    } else if state.mode == .Save {
        _ = fixture_editor_save_path(editor, path)
    } else {
        _ = fixture_editor_load_path(editor, path)
    }
    fixture_editor_file_dialog_close(editor)
}

editor_ui_layout :: proc(editor: ^Editor, width, height: i32) -> Editor_UI_Layout {
    w, h := f32(width), f32(height)
    left_allowed := width >= 800
    inspector_allowed := width >= 1100
    left_visible := left_allowed && (editor == nil || !editor.editor_ui.left_collapsed)
    inspector_visible := inspector_allowed && (editor == nil || !editor.editor_ui.inspector_collapsed)
    result := Editor_UI_Layout {
        top               = {0, 0, w, EDITOR_UI_TOP_HEIGHT},
        left              = {
            EDITOR_UI_GUTTER,
            EDITOR_UI_TOP_HEIGHT + EDITOR_UI_GUTTER,
            EDITOR_UI_RAIL_WIDTH,
            max(h - EDITOR_UI_TOP_HEIGHT - EDITOR_UI_GUTTER * 2, f32(0)),
        },
        inspector         = {
            w - EDITOR_UI_INSPECTOR_WIDTH - EDITOR_UI_GUTTER,
            EDITOR_UI_TOP_HEIGHT + EDITOR_UI_GUTTER,
            EDITOR_UI_INSPECTOR_WIDTH,
            max(h - EDITOR_UI_TOP_HEIGHT - EDITOR_UI_GUTTER * 2, f32(0)),
        },
        left_toggle       = {EDITOR_UI_GUTTER, EDITOR_UI_TOP_HEIGHT + EDITOR_UI_GUTTER, 42, 34},
        inspector_toggle  = {w - EDITOR_UI_GUTTER - 42, EDITOR_UI_TOP_HEIGHT + EDITOR_UI_GUTTER, 42, 34},
        left_visible      = left_visible,
        inspector_visible = inspector_visible,
    }
    hint_left := left_visible ? result.left.x + result.left.width + EDITOR_UI_GUTTER : EDITOR_UI_GUTTER
    hint_right := inspector_visible ? result.inspector.x - EDITOR_UI_GUTTER : w - EDITOR_UI_GUTTER
    result.hint = {hint_left, h - 42, max(hint_right - hint_left, f32(0)), 30}
    return result
}

@(no_instrumentation)
editor_ui_tool_bounds :: #force_inline proc(layout: Editor_UI_Layout, index: int) -> canvas2d.Rectangle {
    column := index % EDITOR_UI_TOOL_COLUMNS
    row := index / EDITOR_UI_TOOL_COLUMNS
    return {
        layout.left.x + 10 + f32(column) * (EDITOR_UI_TOOL_BUTTON_SIZE + EDITOR_UI_TOOL_BUTTON_GAP),
        layout.left.y + 88 + f32(row) * (EDITOR_UI_TOOL_BUTTON_SIZE + EDITOR_UI_TOOL_BUTTON_GAP),
        EDITOR_UI_TOOL_BUTTON_SIZE,
        EDITOR_UI_TOOL_BUTTON_SIZE,
    }
}

editor_ui_draw_tool_icon :: proc(editor: ^Editor, atlas_index: int, bounds: canvas2d.Rectangle, tint: canvas2d.Color) {
    if editor == nil || !editor.authoring_tool_atlas.ready do return
    atlas_columns := f32(4)
    atlas_rows := f32(4)
    cell_width := f32(editor.authoring_tool_atlas.width) / atlas_columns
    cell_height := f32(editor.authoring_tool_atlas.height) / atlas_rows
    source := canvas2d.Rectangle {
        f32(atlas_index % 4) * cell_width,
        f32(atlas_index / 4) * cell_height,
        cell_width,
        cell_height,
    }
    icon_padding := f32(5)
    destination := canvas2d.Rectangle {
        bounds.x + icon_padding,
        bounds.y + icon_padding,
        bounds.width - icon_padding * 2,
        bounds.height - icon_padding * 2,
    }
    canvas2d.DrawTexturePro(editor.authoring_tool_atlas, source, destination, tint)
}

editor_ui_draw_sculpt_icon :: proc(editor: ^Editor, atlas_index: int, bounds: canvas2d.Rectangle) {
    if editor == nil || !editor.sculpt_tool_atlas.ready do return
    cell_width := f32(editor.sculpt_tool_atlas.width) / 5
    source := canvas2d.Rectangle{f32(atlas_index) * cell_width, 0, cell_width, f32(editor.sculpt_tool_atlas.height)}
    size := min(bounds.width - 8, bounds.height - 6)
    destination := canvas2d.Rectangle {
        bounds.x + (bounds.width - size) * .5,
        bounds.y + (bounds.height - size) * .5,
        size,
        size,
    }
    canvas2d.DrawTexturePro(editor.sculpt_tool_atlas, source, destination, {255, 255, 255, 255})
}

editor_ui_draw_tooltip :: proc(bounds: canvas2d.Rectangle, tool: Authoring_Tool) {
    name := authoring_tool_name(tool)
    shortcut := authoring_tool_shortcut(tool)
    label: cstring = shortcut == "" ? name : fmt.ctprintf("%s  [%s]", name, shortcut)
    size := ui_measure_text(.Label, label, .5)
    tooltip := canvas2d.Rectangle{bounds.x + bounds.width + 8, bounds.y + 7, size.x + 20, 30}
    canvas2d.DrawRectangleRounded(tooltip, .14, 5, {17, 20, 24, 252})
    canvas2d.DrawRectangleRoundedLinesEx(tooltip, .14, 5, 1, {89, 101, 114, 255})
    ui_draw_text(.Label, label, {tooltip.x + 10, tooltip.y + 8}, .5, {235, 239, 243, 255})
}

@(no_instrumentation)
editor_ui_fixture_action_bounds :: #force_inline proc(layout: Editor_UI_Layout, index: int) -> canvas2d.Rectangle {
    gap := f32(6)
    width := (layout.left.width - 26 - gap) * .5
    return {layout.left.x + 10 + f32(index) * (width + gap), layout.left.y + 45, width, 30}
}

@(no_instrumentation)
editor_ui_focus_bounds :: #force_inline proc(layout: Editor_UI_Layout) -> canvas2d.Rectangle {
    return {layout.left.x + 10, layout.left.y + layout.left.height - 88, layout.left.width - 20, 32}
}

@(no_instrumentation)
editor_ui_spawn_bounds :: #force_inline proc(layout: Editor_UI_Layout) -> canvas2d.Rectangle {
    return {layout.left.x + 10, layout.left.y + layout.left.height - 46, layout.left.width - 20, 36}
}

editor_ui_panel_button :: proc(
    bounds: canvas2d.Rectangle,
    label: cstring,
    selected: bool = false,
    enabled: bool = true,
) {
    hovered := enabled && canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
    fill := canvas2d.Color{35, 39, 46, 246}
    border := canvas2d.Color{73, 81, 92, 255}
    text := canvas2d.Color{226, 231, 236, 255}
    if hovered {
        fill = {48, 55, 64, 250}
        border = {104, 116, 128, 255}
    }
    if selected {
        fill = {35, 91, 94, 255}
        border = {82, 207, 198, 255}
        text = {244, 255, 254, 255}
    }
    if !enabled {
        fill = {29, 32, 37, 230}
        border = {52, 57, 64, 255}
        text = {105, 112, 120, 255}
    }
    canvas2d.DrawRectangleRounded(bounds, .12, 6, fill)
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .12, 6, selected ? 2 : 1, border)
    size := ui_measure_text(.Label, label, .5)
    ui_draw_text(
        .Label,
        label,
        {
            bounds.x + (bounds.width - size.x) * .5,
            bounds.y + (bounds.height - size.y) * .5 + EDITOR_UI_BUTTON_TEXT_Y_OFFSET,
        },
        .5,
        text,
    )
}

editor_ui_section_title :: proc(label: cstring, x, y, width: f32) {
    ui_draw_text(.Label, label, {x, y}, .5, {145, 155, 166, 255})
    canvas2d.DrawLineEx({x, y + 22}, {x + width, y + 22}, 1, {58, 65, 74, 255})
}

@(no_instrumentation)
editor_ui_slider_bounds :: #force_inline proc(layout: Editor_UI_Layout, row: int) -> canvas2d.Rectangle {
    return {layout.inspector.x + 14, layout.inspector.y + 82 + f32(row) * 48, layout.inspector.width - 28, 42}
}

editor_ui_slider_draw :: proc(
    bounds: canvas2d.Rectangle,
    label: cstring,
    value, minimum, maximum: f32,
    decimals: int = 1,
) {
    normalized := clamp((value - minimum) / max(maximum - minimum, f32(.0001)), 0, 1)
    value_text: cstring
    if decimals <= 0 {
        value_text = fmt.ctprintf("%.0f", value)
    } else if decimals == 1 {
        value_text = fmt.ctprintf("%.1f", value)
    } else {
        value_text = fmt.ctprintf("%.2f", value)
    }
    ui_draw_text(.Label, label, {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
    value_size := ui_measure_text(.Data, value_text, .5)
    ui_draw_text(.Data, value_text, {bounds.x + bounds.width - value_size.x, bounds.y}, .5, {134, 224, 216, 255})
    track := canvas2d.Rectangle{bounds.x, bounds.y + 27, bounds.width, 6}
    canvas2d.DrawRectangleRounded(track, 1, 4, {50, 56, 64, 255})
    canvas2d.DrawRectangleRounded(
        {track.x, track.y, track.width * normalized, track.height},
        1,
        4,
        {60, 164, 157, 255},
    )
    canvas2d.DrawCircleV({track.x + track.width * normalized, track.y + 3}, 6, {221, 238, 237, 255})
}

editor_ui_slider_input :: proc(
    editor: ^Editor,
    layout: Editor_UI_Layout,
    slider_id, row: int,
    value: ^f32,
    minimum, maximum, step: f32,
    history: int = 0,
) -> bool {
    if editor == nil || value == nil || !layout.inspector_visible do return false
    bounds := editor_ui_slider_bounds(layout, row)
    mouse := canvas2d.GetMousePosition()
    if canvas2d.IsMouseButtonPressed(.LEFT) && canvas2d.CheckCollisionPointRec(mouse, bounds) {
        editor.editor_ui.active_slider = slider_id
        if history == 1 {
            terrain_history_push_undo(editor)
        } else if history == 2 {
            structure_history_push_undo(editor)
        }
    }
    if editor.editor_ui.active_slider != slider_id do return false
    if canvas2d.IsMouseButtonReleased(.LEFT) {
        editor.editor_ui.active_slider = 0
        return false
    }
    if !canvas2d.IsMouseButtonDown(.LEFT) do return false
    normalized := clamp((mouse.x - bounds.x) / bounds.width, 0, 1)
    next := minimum + normalized * (maximum - minimum)
    if step > 0 {
        next = f32(int(next / step + .5)) * step
    }
    next = clamp(next, minimum, maximum)
    changed := next != value^
    value^ = next
    return changed
}

@(no_instrumentation)
editor_ui_small_action_bounds :: #force_inline proc(layout: Editor_UI_Layout, index: int) -> canvas2d.Rectangle {
    gap := f32(6)
    width := (layout.inspector.width - 28 - gap) * .5
    return {
        layout.inspector.x + 14 + f32(index % 2) * (width + gap),
        layout.inspector.y + layout.inspector.height - 82 + f32(index / 2) * 35,
        width,
        29,
    }
}

editor_ui_context_message :: proc(editor: ^Editor) -> cstring {
    if editor == nil do return ""
    if editor.selection_tool_active {
        if editor.structure_moving do return "Move the selected item; release to commit."
        if editor.structure_selected >= 0 do return "Drag to move. R rotates; Alt-wheel edits height; Shift-wheel edits size; Backspace deletes."
        return "Click an item to select it."
    }
    if fixture_note_placement_active() do return "Place note: left-click terrain to commit; right-click or Escape cancels."
    if editor.rock_placement_mode do return "Left spawns rocks; right erases rocks. Drag to build clusters; adjust density in the inspector."
    if editor.marina_paint_mode {
        switch editor.marina_brush_status {
        case .Preview:
            return "Preview ready. Right-click rerolls this site; left-click stamps the current marina."
        case .Placed:
            return "Marina stamped. Move to find another site, or undo to remove it."
        case .Unsuitable:
            return "No marina: this shoreline lacks suitable land and protected water."
        case .No_Valid_Layout:
            return "No marina: the site scored well, but no valid layout fit after the bounded search."
        case .Removed:
            return "Marina removed. Left-click near a shoreline to place one."
        case .Idle:
        }
    }
    if editor.road_mode {
        if editor.road_drag_node >= 0 && editor.road_drag_node_moved do return "Drag the road node into place; connected curves follow it."
        if editor.road_drag_edge >= 0 do return "Drag the control handle to shape the road; release to commit."
        if editor.road_construction_phase == .Drag_Start_Tangent do return "Drag away from the start to set its tangent; release to choose an endpoint."
        if editor.road_construction_phase == .Drag_End_Tangent do return "Drag the endpoint handle; release to commit the authored curve."
        if editor.road_preview_status != .Idle && editor.road_preview_status != .Valid {
            return road_preview_status_text(editor.road_preview_status)
        }
        if editor.road_preview_status == .Valid {
            return fmt.ctprintf(
                "Preview ready — %.0fm, %.0f°, rise %+.1fm, max grade %.0f%%. Click to commit.",
                editor.road_preview_distance,
                editor.road_preview_angle,
                editor.road_preview_rise,
                editor.road_preview_maximum_grade * 100,
            )
        }
        if editor.road_selected_node >= 0 {
            if editor.road_construction_mode == .Authored_Curve do return "Click-drag the selected node to set the start tangent."
            if editor.road_hover_edge >= 0 do return "Drag the white curve handle to reshape the road; release to commit."
            return "Drag a cyan curve handle to reshape the road, or move away to preview a new route."
        }
        return "Click terrain to place the first road node; K cycles road surfaces."
    }
    if editor.architecture_paint_mode do return "Drag to orient one settlement piece; release to stamp. Right-drag erases."
    if editor.curve_drawing do return editor.curve_cliff_mode ? "Draw the cliff path; release to commit." : "Draw the ridge path; release to commit."
    if editor.formation_brush_painting do return "Release to commit the brush stroke."
    if editor.structure_placing do return "Drag the footprint; wheel zooms; Shift changes size; Alt changes height."
    if editor.structure_moving do return "Move the selected formation; release to commit."
    switch editor.authoring_tool {
    case .Sculpt:
        if editor.terrain_sculpt.session.active {
            if editor.terrain_sculpt.action == .Grade && !editor.terrain_sculpt.session.grade_valid {
                return "Grade is too steep. Adjust the path or maximum grade."
            }
            if editor.terrain_sculpt.action == .Pad {
                return fmt.ctprintf(
                    "Cut %.0f m³ · Fill %.0f m³. Release to commit.",
                    editor.terrain_sculpt.session.cut_volume,
                    editor.terrain_sculpt.session.fill_volume,
                )
            }
            if editor.terrain_sculpt.session.effective_resolution > terrain.FINE_CELL_SIZE {
                return fmt.ctprintf(
                    "Editing at %.0f m resolution. Release to commit.",
                    editor.terrain_sculpt.session.effective_resolution,
                )
            }
            return(
                editor.terrain_sculpt.session.valid ? "Release to commit. Esc cancels." : "Keep the gesture on one island." \
            )
        }
        switch editor.terrain_sculpt.action {
        case .Coast:
            return "Left pushes the coast out; right pulls it in."
        case .Shelf:
            return "Brush a shallow coastal shelf."
        case .Ridge:
            return "Draw a ridge spine; release to commit."
        case .Valley:
            return "Draw a valley path; release to commit."
        case .Slope:
            return "Draw the slope boundary; the left side is high."
        case .Grade:
            return "Draw a grade between sampled endpoint elevations."
        case .Relax:
            return "Brush to relax steep ground."
        case .Erode:
            return "Brush to erode and transport loose ground."
        case .Deposit:
            return "Brush to deposit material in local lows."
        case .Roughen:
            return "Brush deterministic surface variation."
        case .Terrace:
            return "Brush terrain into elevation steps."
        case .Pad:
            return "Drag a rectangular level pad."
        case .Cut_Fill:
            return "Brush toward the target elevation."
        }
        return "Drag terrain to edit it."
    case .Smooth:
        return "[Left or Right] to smooth   [Wheel] to zoom"
    case .Paint:
        return "[Left] to paint   [Right] to erase   [Wheel] to zoom"
    case .Formations:
        return "[Left] to stamp   [Right] to erase   [Wheel] to zoom"
    case .Foliage:
        if editor.plant_stamp_mode == .Climbing {
            if editor.plant_stamp_target_valid {
                return "Left stamps the previewed climber onto this surface; right erases it."
            }
            return "Hover a building, rock, ridge, cliff, spire, or mountain to attach a climber."
        }
        if editor.foliage_hedgerow_mode {
            return "Drag a cheap hedgerow. Radius controls its width and height."
        }
        return "Left stamps foliage; right erases. Wheel zooms; Shift density; Alt hardness."
    case .Ridge:
        return "Draw a freehand ridge. Wheel zooms; Shift adjusts width and height."
    case .Cliff:
        return "Draw a terrain cliff; the left side of the stroke is high. Reverse direction to flip it."
    case .Building:
        if editor.airport_stamp_mode {
            return "Left stamps an airport; right removes one. Wheel rotates the terminal."
        }
        return "Choose a shape and preset, then drag to orient it. Left adds; right erases."
    case .Marina:
        return "Left places a complete shoreline-oriented marina; right removes it."
    case .Farm:
        return "Left places the previewed farm; right generates a new seed."
    case .Wreck:
        return "Left places the previewed wreck; right generates a new seed."
    case .ClimbingLeaves:
        return "Choose Ground or Climber in Plant Stamp."
    case .Roads:
        return "Click terrain to add spline nodes; drag nodes or handles to reshape roads and steps."
    case .GreekAssets:
        return "Click an asset, then click terrain to place it. Wheel zooms; Alt rotates; Shift scales."
    case .Obstacles:
        return ""
    }
    return ""
}

editor_ui_draw_left :: proc(editor: ^Editor, layout: Editor_UI_Layout) {
    if !layout.left_visible {
        editor_ui_panel_button(layout.left_toggle, ">>")
        return
    }
    canvas2d.DrawRectangleRounded(layout.left, .025, 6, {25, 28, 33, 248})
    canvas2d.DrawRectangleRoundedLinesEx(layout.left, .025, 6, 1, {62, 69, 78, 255})
    ui_draw_text(.Heading, "TOOLS", {layout.left.x + 12, layout.left.y + 14}, .5, {235, 239, 243, 255})
    editor_ui_panel_button({layout.left.x + layout.left.width - 39, layout.left.y + 10, 29, 28}, "<<")
    editor_ui_panel_button(editor_ui_fixture_action_bounds(layout, 0), "SAVE", false, true)
    editor_ui_panel_button(editor_ui_fixture_action_bounds(layout, 1), "LOAD", false, true)
    hovered_tool := -1
    for index in 0 ..< AUTHORING_TOOL_PALETTE_COUNT {
        bounds := editor_ui_tool_bounds(layout, index)
        select_tool := index == 0
        display_index := index - 1
        rock_tool := display_index == AUTHORING_TOOL_DISPLAY_COUNT
        tool := rock_tool || select_tool ? Authoring_Tool.Formations : AUTHORING_TOOL_DISPLAY_ORDER[display_index]
        selected :=
            select_tool ? editor.selection_tool_active : rock_tool ? editor.rock_placement_mode : !editor.selection_tool_active && editor.authoring_tool == tool && !(tool == .Formations && editor.rock_placement_mode)
        hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
        fill := selected ? canvas2d.Color{35, 91, 94, 255} : canvas2d.Color{35, 39, 46, 246}
        if hovered && !selected do fill = {48, 55, 64, 250}
        border := selected ? canvas2d.Color{82, 207, 198, 255} : canvas2d.Color{66, 74, 84, 255}
        canvas2d.DrawRectangleRounded(bounds, .10, 6, fill)
        canvas2d.DrawRectangleRoundedLinesEx(bounds, .10, 6, selected ? 2 : 1, border)
        icon_tint := selected ? canvas2d.Color{255, 255, 255, 255} : canvas2d.Color{225, 231, 235, 255}
        if select_tool {
            // A compact pointer glyph keeps Select distinct from placement art.
            canvas2d.DrawLineEx({bounds.x + 14, bounds.y + 10}, {bounds.x + 14, bounds.y + 37}, 3, icon_tint)
            canvas2d.DrawLineEx({bounds.x + 14, bounds.y + 10}, {bounds.x + 34, bounds.y + 30}, 3, icon_tint)
            canvas2d.DrawLineEx({bounds.x + 14, bounds.y + 37}, {bounds.x + 34, bounds.y + 30}, 3, icon_tint)
            canvas2d.DrawLineEx({bounds.x + 24, bounds.y + 29}, {bounds.x + 34, bounds.y + 40}, 4, icon_tint)
        } else {
            editor_ui_draw_tool_icon(editor, rock_tool ? int(Authoring_Tool.Formations) : int(tool), bounds, icon_tint)
        }
        if hovered do hovered_tool = index
    }
    if hovered_tool >= 0 {
        if hovered_tool == 0 {
            bounds := editor_ui_tool_bounds(layout, hovered_tool)
            size := ui_measure_text(.Label, "SELECT  [S]", .5)
            tooltip := canvas2d.Rectangle{bounds.x + bounds.width + 8, bounds.y + 7, size.x + 20, 30}
            canvas2d.DrawRectangleRounded(tooltip, .14, 5, {17, 20, 24, 252})
            canvas2d.DrawRectangleRoundedLinesEx(tooltip, .14, 5, 1, {89, 101, 114, 255})
            ui_draw_text(.Label, "SELECT  [S]", {tooltip.x + 10, tooltip.y + 8}, .5, {235, 239, 243, 255})
        } else if hovered_tool - 1 == AUTHORING_TOOL_DISPLAY_COUNT {
            bounds := editor_ui_tool_bounds(layout, hovered_tool)
            size := ui_measure_text(.Label, "ROCKS", .5)
            tooltip := canvas2d.Rectangle{bounds.x + bounds.width + 8, bounds.y + 7, size.x + 20, 30}
            canvas2d.DrawRectangleRounded(tooltip, .14, 5, {17, 20, 24, 252})
            canvas2d.DrawRectangleRoundedLinesEx(tooltip, .14, 5, 1, {89, 101, 114, 255})
            ui_draw_text(.Label, "ROCKS", {tooltip.x + 10, tooltip.y + 8}, .5, {235, 239, 243, 255})
        } else {
            editor_ui_draw_tooltip(
                editor_ui_tool_bounds(layout, hovered_tool),
                AUTHORING_TOOL_DISPLAY_ORDER[hovered_tool - 1],
            )
        }
    }
    editor_ui_panel_button(editor_ui_focus_bounds(layout), "FOCUS  [F]")
    editor_ui_panel_button(editor_ui_spawn_bounds(layout), "ENTER WORLD")
}

editor_ui_draw_inspector :: proc(editor: ^Editor, layout: Editor_UI_Layout) {
    if !layout.inspector_visible {
        editor_ui_panel_button(layout.inspector_toggle, "<<")
        return
    }
    panel := layout.inspector
    canvas2d.DrawRectangleRounded(panel, .025, 6, {25, 28, 33, 248})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .025, 6, 1, {62, 69, 78, 255})
    ui_draw_text(
        .Heading,
        editor.selection_tool_active ? "SELECT" : editor.rock_placement_mode ? "ROCKS" : authoring_tool_name(editor.authoring_tool),
        {panel.x + 14, panel.y + 14},
        .5,
        {235, 239, 243, 255},
    )
    editor_ui_panel_button({panel.x + panel.width - 39, panel.y + 10, 29, 28}, ">>")
    editor_ui_section_title("TOOL SETTINGS", panel.x + 14, panel.y + 50, panel.width - 28)

    if editor.selection_tool_active {
        if editor.structure_selected >= 0 && editor.structure_selected < editor.project.structure_count {
            structure := editor.project.structures[editor.structure_selected]
            ui_draw_text(
                .Label,
                formation_kind_name(structure.kind),
                {panel.x + 14, panel.y + 88},
                .5,
                {209, 215, 222, 255},
            )
            row := 1
            cell := editor.project.levels[0].cell_size
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "WIDTH (m)", structure.width, cell, 400, 1)
            row += 1
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "DEPTH (m)", structure.depth, cell, 400, 1)
            row += 1
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "HEIGHT (m)", structure.height, cell, 400, 1)
            row += 1
            ui_draw_text(.Data, "DRAG  MOVE", {panel.x + 14, panel.y + 82 + f32(row) * 48}, .4, {139, 149, 160, 255})
            ui_draw_text(.Data, "R  ROTATE", {panel.x + 14, panel.y + 106 + f32(row) * 48}, .4, {139, 149, 160, 255})
            ui_draw_text(
                .Data,
                "BACKSPACE  DELETE",
                {panel.x + 14, panel.y + 130 + f32(row) * 48},
                .4,
                {139, 149, 160, 255},
            )
        } else if editor.island_selected != .World {
            center_x, center_z, center_ok := terrain.island_center(&editor.project, editor.island_selected)
            if center_ok {
                other := editor.island_selected == .West ? terrain.Island_ID.East : terrain.Island_ID.West
                other_x, other_z, _ := terrain.island_center(&editor.project, other)
                dx, dz := center_x - other_x, center_z - other_z
                distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
                ui_draw_text(.Label, "ISLAND", {panel.x + 14, panel.y + 88}, .5, {209, 215, 222, 255})
                editor_ui_slider_draw(editor_ui_slider_bounds(layout, 1), "CENTER X (m)", center_x, -4000, 4000, 0)
                editor_ui_slider_draw(editor_ui_slider_bounds(layout, 2), "CENTER Z (m)", center_z, -4000, 4000, 0)
                editor_ui_slider_draw(editor_ui_slider_bounds(layout, 3), "DISTANCE (m)", distance, 0, 8000, 0)
                ui_draw_text(.Data, "DRAG  MOVE", {panel.x + 14, panel.y + 282}, .4, {139, 149, 160, 255})
            }
        } else {
            ui_draw_text(.Data, "CLICK AN ITEM OR ISLAND", {panel.x + 14, panel.y + 88}, .5, {139, 149, 160, 255})
        }
        return
    }

    row := 0
    switch editor.authoring_tool {
    case .Sculpt:
        family_bounds := editor_ui_slider_bounds(layout, row)
        family_width := (family_bounds.width - 9) * .25
        for family_index in 0 ..< 4 {
            family := Terrain_Family(family_index)
            editor_ui_panel_button(
                {family_bounds.x + f32(family_index) * (family_width + 3), family_bounds.y + 20, family_width, 30},
                terrain_family_name(family),
                editor.terrain_sculpt.family == family,
            )
        }
        row += 1
        actions, action_count := terrain_family_actions(editor.terrain_sculpt.family)
        action_bounds := editor_ui_slider_bounds(layout, row)
        action_width := (action_bounds.width - f32(action_count - 1) * 4) / f32(action_count)
        for action_index in 0 ..< action_count {
            action := actions[action_index]
            editor_ui_panel_button(
                {action_bounds.x + f32(action_index) * (action_width + 4), action_bounds.y + 20, action_width, 30},
                terrain_action_name(action),
                editor.terrain_sculpt.action == action,
            )
        }
        row += 1
        settings := editor.terrain_sculpt.settings[int(editor.terrain_sculpt.action)]
        editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "SIZE (m)", settings.size, 4, 500, 0)
        row += 1
        editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "FEATHER (m)", settings.feather, 0, 250, 0)
        row += 1
        editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "FLOW", settings.flow, 0, 1, 2)
        row += 1
        switch editor.terrain_sculpt.action {
        case .Coast:
            editor_ui_slider_draw(
                editor_ui_slider_bounds(layout, row),
                "BEACH (m)",
                settings.beach_elevation,
                -5,
                20,
                1,
            )
            row += 1
        case .Shelf:
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "DEPTH (m)", settings.shelf_depth, -80, 0, 1)
            row += 1
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "SLOPE", settings.shelf_slope, .1, 4, 2)
            row += 1
        case .Ridge, .Valley, .Slope:
            editor_ui_slider_draw(
                editor_ui_slider_bounds(layout, row),
                editor.terrain_sculpt.action == .Valley ? "DEPTH (m)" : "HEIGHT (m)",
                settings.height,
                1,
                200,
                0,
            )
            row += 1
        case .Grade:
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "MAX GRADE", settings.maximum_grade, 0, .5, 2)
            row += 1
            grade_mode_bounds := editor_ui_slider_bounds(layout, row)
            editor_ui_panel_button(
                {grade_mode_bounds.x, grade_mode_bounds.y + 20, grade_mode_bounds.width, 30},
                settings.elevation_mode == .Sampled ? "ENDPOINTS: SAMPLED" : "ENDPOINTS: EXPLICIT",
                settings.elevation_mode == .Explicit,
            )
            row += 1
            if settings.elevation_mode == .Explicit {
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "START (m)",
                    settings.grade_start_elevation,
                    -50,
                    300,
                    1,
                ); row += 1
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "END (m)",
                    settings.grade_end_elevation,
                    -50,
                    300,
                    1,
                ); row += 1
            }
        case .Relax, .Erode, .Deposit:
            editor_ui_slider_draw(
                editor_ui_slider_bounds(layout, row),
                "ITERATIONS",
                f32(settings.iterations),
                1,
                96,
                0,
            )
            row += 1
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "TALUS", settings.talus, 0, 4, 2)
            row += 1
        case .Roughen:
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "AMPLITUDE (m)", settings.amplitude, 0, 40, 1)
            row += 1
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "SCALE (m)", settings.noise_scale, 2, 200, 0)
            row += 1
        case .Terrace:
            editor_ui_slider_draw(
                editor_ui_slider_bounds(layout, row),
                "STEP HEIGHT",
                settings.terrace_height,
                .5,
                20,
                1,
            )
            row += 1
            editor_ui_slider_draw(
                editor_ui_slider_bounds(layout, row),
                "REFERENCE",
                settings.terrace_reference,
                -50,
                200,
                1,
            )
            row += 1
        case .Pad, .Cut_Fill:
            editor_ui_slider_draw(
                editor_ui_slider_bounds(layout, row),
                "ELEVATION",
                settings.target_elevation,
                -50,
                300,
                1,
            )
            row += 1
        }
        advanced_bounds := editor_ui_slider_bounds(layout, row)
        editor_ui_panel_button(
            {advanced_bounds.x, advanced_bounds.y + 20, advanced_bounds.width, 30},
            editor.terrain_sculpt.advanced ? "ADVANCED −" : "ADVANCED +",
            editor.terrain_sculpt.advanced,
        )
        row += 1
        if editor.terrain_sculpt.advanced {
            seabed_bounds := editor_ui_slider_bounds(layout, row)
            editor_ui_panel_button(
                {seabed_bounds.x, seabed_bounds.y + 20, seabed_bounds.width, 30},
                settings.affect_seabed ? "AFFECT SEABED: YES" : "AFFECT SEABED: NO",
                settings.affect_seabed,
            )
            row += 1
            editor_ui_slider_draw(
                editor_ui_slider_bounds(layout, row),
                "SPACING",
                settings.spacing,
                .05,
                1,
                2,
            ); row += 1
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "CORE", settings.inner_core, 0, 1, 2); row += 1
            #partial switch editor.terrain_sculpt.action {
            case .Ridge, .Valley:
                profile_bounds := editor_ui_slider_bounds(layout, row)
                third := (profile_bounds.width - 8) / 3
                editor_ui_panel_button(
                    {profile_bounds.x, profile_bounds.y + 20, third, 30},
                    "ROUND",
                    settings.profile == .Round,
                )
                editor_ui_panel_button(
                    {profile_bounds.x + third + 4, profile_bounds.y + 20, third, 30},
                    "SHARP",
                    settings.profile == .Sharp,
                )
                editor_ui_panel_button(
                    {profile_bounds.x + (third + 4) * 2, profile_bounds.y + 20, third, 30},
                    "CLIFF",
                    settings.profile == .Cliff,
                )
                row += 1
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "SIDE BIAS",
                    settings.side_bias,
                    -1,
                    1,
                    2,
                ); row += 1
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "ROUGHNESS",
                    settings.roughness,
                    0,
                    20,
                    1,
                ); row += 1
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "END TAPER",
                    settings.endpoint_taper,
                    0,
                    .5,
                    2,
                ); row += 1
            case .Slope:
                editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "SIDE BIAS", settings.side_bias, -1, 1, 2)
                row += 1
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "PRESERVE DETAIL",
                    settings.preserve_detail,
                    0,
                    1,
                    2,
                )
                row += 1
            case .Erode:
                editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "RAINFALL", settings.rainfall, .01, 2, 2)
                row += 1
                editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "SEDIMENT", settings.sediment, .01, 2, 2)
                row += 1
            case .Roughen:
                editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "OCTAVES", f32(settings.octaves), 1, 6, 0)
                row += 1
            case .Terrace:
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "STEP DEPTH",
                    settings.terrace_depth,
                    1,
                    50,
                    1,
                )
                row += 1
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "RETAINING SLOPE",
                    settings.retaining_slope,
                    0,
                    1,
                    2,
                )
                row += 1
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "IRREGULARITY",
                    settings.irregularity,
                    0,
                    1,
                    2,
                )
                row += 1
            case .Pad:
                editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "EDGE SLOPE", settings.edge_slope, 0, 1, 2)
                row += 1
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "CORNER RADIUS",
                    settings.corner_radius,
                    0,
                    50,
                    1,
                )
                row += 1
            case .Cut_Fill:
                editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "CUT LIMIT", settings.cut_limit, 0, 100, 1)
                row += 1
                editor_ui_slider_draw(
                    editor_ui_slider_bounds(layout, row),
                    "FILL LIMIT",
                    settings.fill_limit,
                    0,
                    100,
                    1,
                )
                row += 1
            }
        }
    case .Smooth, .Paint:
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "RADIUS (m)",
            editor.radius,
            terrain.BASE_CELL_SIZE,
            400,
            0,
        )
        row += 1
        editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "STRENGTH", editor.strength, 0, 1, 2)
        row += 1
        editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "HARDNESS", editor.hardness, 0, 1, 2)
        row += 1
    case .Formations:
        bounds := editor_ui_slider_bounds(layout, row)
        profile :=
            editor.rock_placement_mode ? "ROCK" : editor.structure_auto_kind ? "AUTOMATIC" : formation_kind_name(editor.structure_kind)
        ui_draw_text(.Label, "PROFILE", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        profile_size := ui_measure_text(.Data, profile, .5)
        ui_draw_text(.Data, profile, {bounds.x + bounds.width - profile_size.x, bounds.y}, .5, {134, 224, 216, 255})
        half := (bounds.width - 6) * .5
        if !editor.rock_placement_mode {
            editor_ui_panel_button({bounds.x, bounds.y + 24, half, 30}, "AUTO", editor.structure_auto_kind)
            editor_ui_panel_button(
                {bounds.x + half + 6, bounds.y + 24, half, 30},
                "CYCLE  [V]",
                !editor.structure_auto_kind,
            )
            row += 2
        } else {
            ui_draw_text(.Data, "SMOOTH SHADED · VARIANTS", {bounds.x, bounds.y + 28}, .32, {139, 149, 160, 255})
            row += 1
            material_bounds := editor_ui_slider_bounds(layout, row)
            gap := f32(5)
            third := (material_bounds.width - gap * 2) / 3
            ui_draw_text(.Label, "MATERIAL", {material_bounds.x, material_bounds.y}, .5, {209, 215, 222, 255})
            labels := [3]cstring{"PALE", "GRAY", "DARK"}
            for variant in 0 ..< 3 {
                editor_ui_panel_button(
                    {material_bounds.x + f32(variant) * (third + gap), material_bounds.y + 24, third, 30},
                    labels[variant],
                    editor.rock_material_variant == variant,
                )
            }
            row += 1
        }
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "RADIUS (m)",
            editor.formation_brush_radius,
            terrain.BASE_CELL_SIZE,
            240,
            1,
        )
        row += 1
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "DENSITY",
            editor.formation_brush_strength,
            .02,
            1,
            2,
        )
        row += 1
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "HARDNESS",
            editor.formation_brush_hardness,
            0,
            1,
            2,
        )
        row += 1
        if editor.structure_selected >= 0 && editor.structure_selected < editor.project.structure_count {
            structure := editor.project.structures[editor.structure_selected]
            ui_draw_text(
                .Data,
                fmt.ctprintf("SELECTED  %.0f x %.0f x %.0f m", structure.width, structure.depth, structure.height),
                {panel.x + 14, panel.y + 82 + f32(row) * 48},
                .4,
                {134, 224, 216, 255},
            )
        } else {
            ui_draw_text(
                .Data,
                editor.rock_placement_mode ? "DRAG TO SPAWN ROCKS" : "DRAG TO PLACE FORMATIONS",
                {panel.x + 14, panel.y + 82 + f32(row) * 48},
                .4,
                {139, 149, 160, 255},
            )
        }
    case .Foliage:
        preview_bounds := editor_ui_slider_bounds(layout, row)
        ui_draw_text(.Label, "PLANT PREVIEWS", {preview_bounds.x, preview_bounds.y}, .5, {209, 215, 222, 255})
        preview_gap := f32(8)
        preview_width := (preview_bounds.width - preview_gap) * .5
        ground_preview := canvas2d.Rectangle{preview_bounds.x, preview_bounds.y + 24, preview_width, 70}
        climbing_preview := canvas2d.Rectangle {
            preview_bounds.x + preview_width + preview_gap,
            preview_bounds.y + 24,
            preview_width,
            70,
        }
        ground_button := canvas2d.Rectangle{ground_preview.x, ground_preview.y + 42, ground_preview.width, 28}
        climbing_button := canvas2d.Rectangle{climbing_preview.x, climbing_preview.y + 42, climbing_preview.width, 28}
        editor_ui_panel_button(ground_button, "GROUND", editor.plant_stamp_mode == .Ground)
        editor_ui_panel_button(climbing_button, "CLIMBER", editor.plant_stamp_mode == .Climbing)
        // Small silhouettes make the choice scannable before reading labels.
        canvas2d.DrawCircleV({ground_preview.x + 25, ground_preview.y + 22}, 10, {91, 147, 76, 255})
        canvas2d.DrawCircleV({ground_preview.x + 42, ground_preview.y + 20}, 13, {70, 126, 68, 255})
        canvas2d.DrawRectangleRec({climbing_preview.x + 18, climbing_preview.y + 9, 32, 28}, {146, 133, 108, 255})
        canvas2d.DrawLineEx(
            {climbing_preview.x + 22, climbing_preview.y + 35},
            {climbing_preview.x + 45, climbing_preview.y + 12},
            3,
            {55, 111, 61, 255},
        )
        canvas2d.DrawCircleV({climbing_preview.x + 31, climbing_preview.y + 25}, 5, {76, 143, 72, 255})
        row += 2
        if editor.plant_stamp_mode == .Climbing {
            editor_ui_slider_draw(
                editor_ui_slider_bounds(layout, row),
                "ATTACH RADIUS (m)",
                editor.climbing_leaf_brush_radius,
                terrain.BASE_CELL_SIZE,
                240,
                1,
            )
            row += 1
            editor_ui_slider_draw(
                editor_ui_slider_bounds(layout, row),
                "GROWTH",
                editor.climbing_leaf_brush_strength,
                .02,
                1,
                2,
            )
            row += 1
            status: cstring =
                editor.plant_stamp_target_valid ? "SURFACE READY — CLICK TO ATTACH" : "HOVER AN ELIGIBLE SURFACE"
            status_color :=
                editor.plant_stamp_target_valid ? canvas2d.Color{134, 224, 216, 255} : canvas2d.Color{224, 126, 108, 255}
            ui_draw_text(.Data, status, {panel.x + 14, panel.y + 82 + f32(row) * 48}, .4, status_color)
            break
        }
        bounds := editor_ui_slider_bounds(layout, row)
        ui_draw_text(.Label, "MODE", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        half := (bounds.width - 6) * .5
        editor_ui_panel_button({bounds.x, bounds.y + 24, half, 30}, "MASS", !editor.foliage_hedgerow_mode)
        editor_ui_panel_button({bounds.x + half + 6, bounds.y + 24, half, 30}, "HEDGE", editor.foliage_hedgerow_mode)
        row += 1
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "RADIUS (m)",
            editor.formation_brush_radius,
            terrain.BASE_CELL_SIZE,
            240,
            1,
        )
        row += 1
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "DENSITY",
            editor.formation_brush_strength,
            .02,
            1,
            2,
        )
        row += 1
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "HARDNESS",
            editor.formation_brush_hardness,
            0,
            1,
            2,
        )
        row += 1
        if editor.structure_selected >= 0 && editor.structure_selected < editor.project.structure_count {
            structure := editor.project.structures[editor.structure_selected]
            ui_draw_text(
                .Data,
                fmt.ctprintf("SELECTED  %.0f x %.0f x %.0f m", structure.width, structure.depth, structure.height),
                {panel.x + 14, panel.y + 82 + f32(row) * 48},
                .4,
                {143, 190, 91, 255},
            )
        } else {
            ui_draw_text(
                .Data,
                editor.foliage_hedgerow_mode ? "DRAG A HEDGEROW" : "DRAG TO PLACE FOLIAGE",
                {panel.x + 14, panel.y + 82 + f32(row) * 48},
                .4,
                {139, 149, 160, 255},
            )
        }
    case .Ridge, .Cliff:
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "WIDTH (m)",
            editor.curve_width,
            terrain.BASE_CELL_SIZE,
            terrain.BASE_CELL_SIZE * 16,
            1,
        )
        row += 1
        if editor.authoring_tool == .Cliff {
            bounds := editor_ui_slider_bounds(layout, row)
            gap := f32(5)
            button_width := (bounds.width - gap * 2) / 3
            ui_draw_text(.Label, "ELEVATION", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
            editor_ui_panel_button(
                {bounds.x, bounds.y + 24, button_width, 30},
                "RAISE",
                editor.cliff_elevation_mode == .Raise,
            )
            editor_ui_panel_button(
                {bounds.x + button_width + gap, bounds.y + 24, button_width, 30},
                "LOWER",
                editor.cliff_elevation_mode == .Lower,
            )
            editor_ui_panel_button(
                {bounds.x + (button_width + gap) * 2, bounds.y + 24, button_width, 30},
                "SPLIT",
                editor.cliff_elevation_mode == .Split,
            )
            row += 1
        }
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "HEIGHT (m)",
            editor.curve_height,
            terrain.BASE_CELL_SIZE,
            terrain.BASE_CELL_SIZE * 24,
            1,
        )
        row += 1
    case .Building:
        bounds := editor_ui_slider_bounds(layout, row)
        half := (bounds.width - 6) * .5
        ui_draw_text(.Label, "MODE", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        editor_ui_panel_button({bounds.x, bounds.y + 24, half, 30}, "CITY BRUSH", !editor.airport_stamp_mode)
        editor_ui_panel_button({bounds.x + half + 6, bounds.y + 24, half, 30}, "AIRPORT", editor.airport_stamp_mode)
        row += 1
        if editor.airport_stamp_mode {
            bounds = editor_ui_slider_bounds(layout, row)
            ui_draw_text(.Label, "FOOTPRINT", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
            ui_draw_text(.Data, "42 x 30 m", {bounds.x + 104, bounds.y}, .5, {134, 224, 216, 255})
            label: cstring = editor.airport_preview_valid ? "CLICK TO PLACE AIRPORT" : "SITE MUST BE DRY LAND"
            color :=
                editor.airport_preview_valid ? canvas2d.Color{134, 224, 216, 255} : canvas2d.Color{224, 126, 108, 255}
            ui_draw_text(.Data, label, {bounds.x, bounds.y + 38}, .4, color)
            break
        }
        bounds = editor_ui_slider_bounds(layout, row)
        half = (bounds.width - 6) * .5
        ui_draw_text(.Label, "SHAPE", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        editor_ui_panel_button(
            {bounds.x, bounds.y + 24, half, 30},
            "SQUARE",
            editor.architecture_brush_shape == .Square,
        )
        editor_ui_panel_button(
            {bounds.x + half + 6, bounds.y + 24, half, 30},
            "RECTANGLE",
            editor.architecture_brush_shape == .Rectangle,
        )
        editor_ui_panel_button(
            {bounds.x, bounds.y + 58, half, 30},
            "CIRCLE",
            editor.architecture_brush_shape == .Circle,
        )
        editor_ui_panel_button(
            {bounds.x + half + 6, bounds.y + 58, half, 30},
            "MACARONI",
            editor.architecture_brush_shape == .Macaroni,
        )
        row += 2
        bounds = editor_ui_slider_bounds(layout, row)
        third := (bounds.width - 12) / 3
        ui_draw_text(.Label, "PRESET", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        editor_ui_panel_button(
            {bounds.x, bounds.y + 24, third, 30},
            "SMALL",
            editor.architecture_brush_preset == .Small,
        )
        editor_ui_panel_button(
            {bounds.x + third + 6, bounds.y + 24, third, 30},
            "MEDIUM",
            editor.architecture_brush_preset == .Medium,
        )
        editor_ui_panel_button(
            {bounds.x + (third + 6) * 2, bounds.y + 24, third, 30},
            "LARGE",
            editor.architecture_brush_preset == .Large,
        )
        row += 1
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "DENSITY",
            editor.architecture_brush_strength,
            .02,
            1,
            2,
        )
        row += 1
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "HARDNESS",
            editor.architecture_brush_hardness,
            0,
            1,
            2,
        )
        row += 1
    case .Marina:
        bounds := editor_ui_slider_bounds(layout, row)
        ui_draw_text(.Label, "FOOTPRINT", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        ui_draw_text(.Data, "108 x 84 m", {bounds.x + 104, bounds.y}, .5, {134, 224, 216, 255})
        preview_label: cstring =
            editor.marina_preview_valid ? "CLICK TO PLACE CURRENT MARINA" : "NO SUITABLE CANDIDATE"
        preview_color :=
            editor.marina_preview_valid ? canvas2d.Color{134, 224, 216, 255} : canvas2d.Color{224, 126, 108, 255}
        ui_draw_text(.Data, preview_label, {bounds.x, bounds.y + 38}, .4, preview_color)
        score_color := canvas2d.Color{231, 150, 126, 255}
        if editor.marina_brush_suitability >= MARINA_BRUSH_MINIMUM_SUITABILITY {
            score_color = {134, 224, 216, 255}
        }
        ui_draw_text(
            .Data,
            fmt.ctprintf(
                "LAST SCORE %d%%  TRIES %d",
                int(editor.marina_brush_suitability * 100 + .5),
                editor.marina_brush_attempts,
            ),
            {bounds.x, bounds.y + 66},
            .4,
            score_color,
        )
        if editor.marina_preview_valid {
            ui_draw_text(.Data, "RIGHT CLICK TO REROLL", {bounds.x, bounds.y + 88}, .4, {134, 224, 216, 255})
        }
    case .Wreck:
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "WRECK SIZE (m)",
            editor.wreck_brush_size,
            160,
            520,
            0,
        )
        row += 1
        bounds := editor_ui_slider_bounds(layout, row)
        ui_draw_text(.Label, "FOOTPRINT", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        ui_draw_text(
            .Data,
            fmt.ctprintf("%d x %d m", int(editor.wreck_brush_size), int(editor.wreck_brush_size * 70 / 330)),
            {bounds.x + 104, bounds.y},
            .5,
            {134, 224, 216, 255},
        )
        preview_label: cstring =
            editor.wreck_preview_valid ? "CLICK TO PLACE CURRENT WRECK" : "MOVE AWAY FROM ANOTHER WRECK"
        preview_color :=
            editor.wreck_preview_valid ? canvas2d.Color{134, 224, 216, 255} : canvas2d.Color{224, 126, 108, 255}
        ui_draw_text(.Data, preview_label, {bounds.x, bounds.y + 38}, .4, preview_color)
        if editor.wreck_preview_valid {
            ui_draw_text(.Data, "RIGHT CLICK TO REROLL", {bounds.x, bounds.y + 66}, .4, {134, 224, 216, 255})
        }
    case .Farm:
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "FARM SIZE (m)",
            editor.farm_brush_radius * 2,
            40,
            240,
            0,
        )
        row += 1
        bounds := editor_ui_slider_bounds(layout, row)
        width_m := int(editor.farm_brush_radius * 2 + .5)
        depth_m := int(editor.farm_brush_radius * 2 * f32(farmland.GRID_HEIGHT) / f32(farmland.GRID_WIDTH) + .5)
        ui_draw_text(.Label, "FOOTPRINT", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        ui_draw_text(
            .Data,
            fmt.ctprintf("%d x %d m", width_m, depth_m),
            {bounds.x + 104, bounds.y},
            .5,
            {134, 224, 216, 255},
        )
        preview_label: cstring = editor.farm_preview_valid ? "CLICK TO PLACE FARM" : "NO SUITABLE SITE"
        preview_color :=
            editor.farm_preview_valid ? canvas2d.Color{134, 224, 216, 255} : canvas2d.Color{224, 126, 108, 255}
        ui_draw_text(.Data, preview_label, {bounds.x, bounds.y + 38}, .4, preview_color)
        if editor.farm_preview_valid {
            ui_draw_text(
                .Data,
                fmt.ctprintf(
                    "SCORE %d%%  SITE %d%%  PLAN %d%%",
                    int(editor.farm_preview_score * 100 + .5),
                    int(editor.farm_preview_site_score * 100 + .5),
                    int(editor.farm_preview_generation_score * 100 + .5),
                ),
                {bounds.x, bounds.y + 66},
                .4,
                {143, 190, 91, 255},
            )
            ui_draw_text(.Data, "RIGHT CLICK TO REROLL", {bounds.x, bounds.y + 88}, .4, {134, 224, 216, 255})
        }
    case .ClimbingLeaves:
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "RADIUS (m)",
            editor.climbing_leaf_brush_radius,
            terrain.BASE_CELL_SIZE,
            240,
            1,
        )
        row += 1
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "SPREAD",
            editor.climbing_leaf_brush_strength,
            .02,
            1,
            2,
        )
        row += 1
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "HARDNESS",
            editor.climbing_leaf_brush_hardness,
            0,
            1,
            2,
        )
        row += 1
    case .Obstacles:
        actions := editor_ui_slider_bounds(layout, row)
        half := (actions.width - 6) * .5
        editor_ui_panel_button({actions.x, actions.y + 8, half, 30}, "ADD", false, editor.sdf_obstacle_count < SDF_OBSTACLE_CAPACITY)
        editor_ui_panel_button(
            {actions.x + half + 6, actions.y + 8, half, 30},
            "DELETE",
            false,
            editor.sdf_obstacle_selected >= 0 && editor.sdf_obstacle_selected < editor.sdf_obstacle_count,
        )
        row += 1
        list_bounds := editor_ui_slider_bounds(layout, row)
        editor_ui_section_title(fmt.ctprintf("TORI  %d/%d", editor.sdf_obstacle_count, SDF_OBSTACLE_CAPACITY), list_bounds.x, list_bounds.y, list_bounds.width)
        previous_bounds := canvas2d.Rectangle{list_bounds.x + list_bounds.width - 66, list_bounds.y - 4, 30, 26}
        next_bounds := canvas2d.Rectangle{list_bounds.x + list_bounds.width - 30, list_bounds.y - 4, 30, 26}
        editor_ui_panel_button(previous_bounds, "<", false, editor.sdf_obstacle_interaction.list_scroll > 0)
        editor_ui_panel_button(
            next_bounds,
            ">",
            false,
            editor.sdf_obstacle_interaction.list_scroll < sdf_obstacle_list_scroll_max(editor),
        )
        row += 1
        sdf_obstacle_list_scroll_clamp(editor)
        first := editor.sdf_obstacle_interaction.list_scroll
        visible := min(SDF_OBSTACLE_LIST_VISIBLE_COUNT, editor.sdf_obstacle_count - first)
        for item in 0 ..< visible {
            index := first + item
            entry := editor_ui_slider_bounds(layout, row + item)
            editor_ui_panel_button(entry, fmt.ctprintf("TORUS %02d", index + 1), index == editor.sdf_obstacle_selected)
        }
        row += max(visible, 1)
    case .Roads:
        top_bounds := editor_ui_slider_bounds(layout, row)
        editor_ui_panel_button(
            top_bounds,
            fmt.ctprintf("MODE   %s", road_mode_name(editor.road_construction_mode)),
            true,
            true,
        )
        row += 1
        top_bounds = editor_ui_slider_bounds(layout, row)
        editor_ui_panel_button(
            top_bounds,
            fmt.ctprintf("SURFACE   %s", roads.pavement_name(editor.road_pavement)),
            editor.road_pavement == .Steps,
            true,
        )
        row += 1
        editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "ROAD WIDTH (m)", editor.road_width, 2.5, 24, 1)
        row += 1
        editor_ui_slider_draw(
            editor_ui_slider_bounds(layout, row),
            "SHOULDER (m)",
            editor.road_shoulder_width,
            0,
            8,
            1,
        )
        row += 1
        if editor.road_construction_mode == .Terrain_Route {
            bounds := editor_ui_slider_bounds(layout, row)
            gap := f32(3)
            button_width := (bounds.width - gap * 3) / 4
            labels := [4]cstring{"REC", "CHEAP", "FAST", "LIGHT"}
            for index in 0 ..< 4 {
                editor_ui_panel_button(
                    {bounds.x + f32(index) * (button_width + gap), bounds.y, button_width, 25},
                    labels[index],
                    int(editor.road_design_alternative) == index,
                )
            }
            row += 1
            if editor.road_design_optimizer != nil {
                optimizer := editor.road_design_optimizer
                editor_ui_panel_button(
                    editor_ui_slider_bounds(layout, row),
                    fmt.ctprintf(
                        "%s  GEN %d  EVAL %d",
                        editor.road_design_paused ? "RESUME" : "PAUSE",
                        optimizer.generation,
                        optimizer.evaluations,
                    ),
                    editor.road_design_paused,
                    true,
                )
                row += 1
                selected, selected_ok := road_designer.candidate(optimizer, editor.road_design_alternative)
                if selected_ok {
                    ui_draw_text(
                        .Data,
                        fmt.ctprintf(
                            "C %.0f   T %.1fs   I %.0f",
                            selected.metrics.construction,
                            selected.metrics.travel_seconds,
                            selected.metrics.impact,
                        ),
                        {editor_ui_slider_bounds(layout, row).x + 5, editor_ui_slider_bounds(layout, row).y + 14},
                        .42,
                        {134, 224, 216, 255},
                    )
                    row += 1
                }
            }
        }
        bounds := editor_ui_slider_bounds(layout, row)
        gap := f32(4)
        button_width := (bounds.width - gap * 2) / 3
        labels := [6]cstring{"NODES", "EDGES", "GRID", "ANGLES", "TANGENT", "PERP"}
        values := [6]bool {
            editor.road_snap_nodes,
            editor.road_snap_edges,
            editor.road_snap_grid,
            editor.road_snap_angles,
            editor.road_snap_tangents,
            editor.road_snap_perpendiculars,
        }
        for index in 0 ..< 6 {
            column, toggle_row := index % 3, index / 3
            editor_ui_panel_button(
                {bounds.x + f32(column) * (button_width + gap), bounds.y + f32(toggle_row) * 23, button_width, 20},
                labels[index],
                values[index],
            )
        }
        row += 1
        if editor.road_selected_node >= 0 && editor.road_selected_node < editor.project.road_graph.node_count {
            radius := editor.project.road_graph.nodes[editor.road_selected_node].junction_radius
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "JUNCTION RADIUS", radius, 1, 40, 1)
            row += 1
            if editor.road_construction_mode == .Terrain_Route &&
               roads.node_degree(&editor.project.road_graph, editor.road_selected_node) == 2 {
                editor_ui_panel_button(editor_ui_slider_bounds(layout, row), "REDESIGN SELECTED CHAIN", false, true)
                row += 1
            }
        }
    case .GreekAssets:
        editor_ui_panel_button(
            editor_ui_slider_bounds(layout, row),
            editor.ruin_stamp_aegean ? "REGION   AEGEAN" : "REGION   ADRIATIC",
            editor.ruin_stamp_aegean,
            true,
        )
        row += 1
        editor_ui_panel_button(
            editor_ui_slider_bounds(layout, row),
            editor.ruin_stamp_complex ? "SITE     COMPLEX" : "SITE     SINGLE RUIN",
            editor.ruin_stamp_complex,
            true,
        )
        row += 1
        ui_draw_text(
            .Data,
            fmt.ctprintf("VARIATION %d", editor.ruin_stamp_seed_offset),
            {panel.x + 14, editor_ui_slider_bounds(layout, row).y + 8},
            .4,
            {209, 215, 222, 255},
        )
        row += 1
    }

    world_y := min(panel.y + 82 + f32(max(row, 3)) * 48 + 12, panel.y + panel.height - 174)
    editor_ui_section_title("WORLD", panel.x + 14, world_y, panel.width - 28)
    data_y := world_y + 32
    if editor.cursor_hit {
        ui_draw_text(
            .Data,
            fmt.ctprintf("CURSOR   X %.0f   Z %.0f", editor.cursor_world_x, editor.cursor_world_z),
            {panel.x + 14, data_y},
            .4,
            {209, 215, 222, 255},
        )
        ui_draw_text(
            .Data,
            fmt.ctprintf("HEIGHT   %.2f m   MAT %.2f", editor.cursor_height, editor.cursor_material),
            {panel.x + 14, data_y + 24},
            .4,
            {209, 215, 222, 255},
        )
    } else {
        ui_draw_text(.Data, "CURSOR   —", {panel.x + 14, data_y}, .4, {139, 149, 160, 255})
    }
    undo_enabled := editor.tool == .Structure ? editor.structure_undo_count > 0 : editor.terrain_undo_count > 0
    redo_enabled := editor.tool == .Structure ? editor.structure_redo_count > 0 : editor.terrain_redo_count > 0
    project_dirty := editor.project.revision != editor.terrain_saved_revision
    save_label: cstring = project_dirty ? "SAVE  •" : "SAVE"
    editor_ui_panel_button(editor_ui_small_action_bounds(layout, 0), save_label, project_dirty, true)
    editor_ui_panel_button(editor_ui_small_action_bounds(layout, 1), "LOAD", false, true)
    editor_ui_panel_button(editor_ui_small_action_bounds(layout, 2), "UNDO", false, undo_enabled)
    editor_ui_panel_button(editor_ui_small_action_bounds(layout, 3), "REDO", false, redo_enabled)
}

editor_ui_draw :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil do return
    layout := editor_ui_layout(editor, width, height)
    canvas2d.DrawRectangle(0, 0, width, i32(EDITOR_UI_TOP_HEIGHT), {22, 25, 29, 248})
    canvas2d.DrawLineEx({0, EDITOR_UI_TOP_HEIGHT - 1}, {f32(width), EDITOR_UI_TOP_HEIGHT - 1}, 1, {65, 72, 81, 255})
    fixture_path := fixture_editor_current_path(editor)
    fixture_label: cstring = fixture_path != "" ? fmt.ctprintf("FIXTURE  %s", fixture_path) : "FIXTURE  UNSAVED"
    ui_draw_text(.Data, fixture_label, {16, 18}, .4, {209, 215, 222, 255})
    minutes := int(editor.atmosphere.world_minutes)
    header_status := fmt.ctprintf(
        "TIME  %02d:%02d  %s     OBJECTS  %d forms  %d roads",
        minutes / 60,
        minutes % 60,
        atmosphere.preset_name(editor.atmosphere.override),
        editor.project.structure_count,
        editor.project.road_graph.edge_count,
    )
    header_status_size := ui_measure_text(.Data, header_status, .4)
    header_status_x := f32(width) - header_status_size.x - 16
    ui_draw_text(.Data, header_status, {header_status_x, 18}, .4, {209, 215, 222, 255})
    if editor.terrain_file_status != nil && f32(canvas2d.GetTime()) < editor.terrain_file_status_until {
        status := fmt.ctprintf("%s", editor.terrain_file_status)
        status_size := ui_measure_text(.Data, status, .4)
        ui_draw_text(.Data, status, {header_status_x - status_size.x - 24, 18}, .4, {151, 161, 172, 255})
    }
    editor_ui_draw_left(editor, layout)
    editor_ui_draw_inspector(editor, layout)
    if layout.hint.width > 160 {
        canvas2d.DrawRectangleRounded(layout.hint, .15, 6, {25, 28, 33, 238})
        hint := editor_ui_context_message(editor)
        ui_draw_text(.Data, hint, {layout.hint.x + 12, layout.hint.y + 7}, .3, {214, 220, 226, 255})
    }
}

editor_ui_hit :: proc(editor: ^Editor, position: canvas2d.Vector2, width, height: i32) -> bool {
    if editor == nil do return imgui_captures_mouse()
    if fixture_editor_file_dialog_is_open(editor) do return true
    if editor.in_map do return imgui_captures_mouse()
    layout := editor_ui_layout(editor, width, height)
    if canvas2d.CheckCollisionPointRec(position, layout.top) do return true
    if layout.left_visible && canvas2d.CheckCollisionPointRec(position, layout.left) do return true
    if layout.inspector_visible && canvas2d.CheckCollisionPointRec(position, layout.inspector) do return true
    if !layout.left_visible && canvas2d.CheckCollisionPointRec(position, layout.left_toggle) do return true
    if !layout.inspector_visible && canvas2d.CheckCollisionPointRec(position, layout.inspector_toggle) do return true
    if layout.hint.width > 160 && canvas2d.CheckCollisionPointRec(position, layout.hint) do return true
    return imgui_captures_mouse()
}

editor_ui_process_input :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil || editor.in_map do return
    if fixture_editor_file_dialog_is_open(editor) {
        fixture_file_dialog_poll(editor)
        return
    }
    layout := editor_ui_layout(editor, width, height)
    mouse := canvas2d.GetMousePosition()
    pressed := canvas2d.IsMouseButtonPressed(.LEFT)

    if pressed {
        if layout.left_visible {
            collapse := canvas2d.Rectangle{layout.left.x + layout.left.width - 39, layout.left.y + 10, 29, 28}
            if canvas2d.CheckCollisionPointRec(mouse, collapse) {
                editor.editor_ui.left_collapsed = true
                return
            }
            if canvas2d.CheckCollisionPointRec(mouse, editor_ui_fixture_action_bounds(layout, 0)) {
                fixture_editor_save(editor)
                return
            } else if canvas2d.CheckCollisionPointRec(mouse, editor_ui_fixture_action_bounds(layout, 1)) {
                fixture_editor_restore(editor)
                return
            }
            for index in 0 ..< AUTHORING_TOOL_PALETTE_COUNT {
                if canvas2d.CheckCollisionPointRec(mouse, editor_ui_tool_bounds(layout, index)) {
                    if index == 0 {
                        authoring_select_selection_tool(editor)
                    } else if index - 1 == AUTHORING_TOOL_DISPLAY_COUNT {
                        authoring_select_rock_tool(editor)
                    } else {
                        authoring_select_tool(editor, AUTHORING_TOOL_DISPLAY_ORDER[index - 1])
                    }
                    return
                }
            }
            if canvas2d.CheckCollisionPointRec(mouse, editor_ui_focus_bounds(layout)) {
                editor_focus_terrain(editor)
                return
            }
            if canvas2d.CheckCollisionPointRec(mouse, editor_ui_spawn_bounds(layout)) {
                editor_spawn_into_world(editor)
                return
            }
        } else if canvas2d.CheckCollisionPointRec(mouse, layout.left_toggle) {
            editor.editor_ui.left_collapsed = false
            return
        }
        if layout.inspector_visible {
            collapse := canvas2d.Rectangle {
                layout.inspector.x + layout.inspector.width - 39,
                layout.inspector.y + 10,
                29,
                28,
            }
            if canvas2d.CheckCollisionPointRec(mouse, collapse) {
                editor.editor_ui.inspector_collapsed = true
                return
            }
        } else if canvas2d.CheckCollisionPointRec(mouse, layout.inspector_toggle) {
            editor.editor_ui.inspector_collapsed = false
            return
        }
    }

    if !layout.inspector_visible do return
    if editor.selection_tool_active {
        if editor.structure_selected >= 0 && editor.structure_selected < editor.project.structure_count {
            structure := &editor.project.structures[editor.structure_selected]
            cell := editor.project.levels[0].cell_size
            changed := false
            changed = editor_ui_slider_input(editor, layout, 101, 1, &structure.width, cell, 400, 1, 2) || changed
            changed = editor_ui_slider_input(editor, layout, 102, 2, &structure.depth, cell, 400, 1, 2) || changed
            changed = editor_ui_slider_input(editor, layout, 103, 3, &structure.height, cell, 400, 1, 2) || changed
            if changed do editor.project.revision += 1
        } else if editor.island_selected != .World {
            center_x, center_z, center_ok := terrain.island_center(&editor.project, editor.island_selected)
            if center_ok {
                next_x, next_z := center_x, center_z
                changed_x := editor_ui_slider_input(editor, layout, 201, 1, &next_x, -4000, 4000, 1, 2)
                changed_z := editor_ui_slider_input(editor, layout, 202, 2, &next_z, -4000, 4000, 1, 2)
                if changed_x || changed_z {
                    _ = editor_island_set_center(editor, editor.island_selected, next_x, next_z)
                }
                other := editor.island_selected == .West ? terrain.Island_ID.East : terrain.Island_ID.West
                other_x, other_z, _ := terrain.island_center(&editor.project, other)
                dx, dz := center_x - other_x, center_z - other_z
                distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
                next_distance := distance
                if editor_ui_slider_input(editor, layout, 203, 3, &next_distance, 0, 8000, 1, 2) {
                    distance_x, distance_z, distance_ok := terrain.island_center_at_distance(
                        &editor.project,
                        editor.island_selected,
                        next_distance,
                    )
                    if distance_ok do _ = editor_island_set_center(editor, editor.island_selected, distance_x, distance_z)
                }
            }
        }
        return
    }
    row := 0
    switch editor.authoring_tool {
    case .Sculpt:
        family_bounds := editor_ui_slider_bounds(layout, row)
        family_width := (family_bounds.width - 9) * .25
        if pressed {
            for family_index in 0 ..< 4 {
                button := canvas2d.Rectangle {
                    family_bounds.x + f32(family_index) * (family_width + 3),
                    family_bounds.y + 20,
                    family_width,
                    30,
                }
                if canvas2d.CheckCollisionPointRec(mouse, button) {
                    family := Terrain_Family(family_index)
                    actions, _ := terrain_family_actions(family)
                    terrain_authoring_select(editor, family, actions[0])
                }
            }
        }
        row += 1
        actions, action_count := terrain_family_actions(editor.terrain_sculpt.family)
        action_bounds := editor_ui_slider_bounds(layout, row)
        action_width := (action_bounds.width - f32(action_count - 1) * 4) / f32(action_count)
        if pressed {
            for action_index in 0 ..< action_count {
                button := canvas2d.Rectangle {
                    action_bounds.x + f32(action_index) * (action_width + 4),
                    action_bounds.y + 20,
                    action_width,
                    30,
                }
                if canvas2d.CheckCollisionPointRec(mouse, button) {
                    terrain_authoring_select(editor, editor.terrain_sculpt.family, actions[action_index])
                }
            }
        }
        row += 1
        settings := &editor.terrain_sculpt.settings[int(editor.terrain_sculpt.action)]
        _ = editor_ui_slider_input(editor, layout, 301, row, &settings.size, 4, 500, 1); row += 1
        _ = editor_ui_slider_input(editor, layout, 302, row, &settings.feather, 0, 250, 1); row += 1
        _ = editor_ui_slider_input(editor, layout, 303, row, &settings.flow, 0, 1, .01); row += 1
        switch editor.terrain_sculpt.action {
        case .Coast:
            _ = editor_ui_slider_input(editor, layout, 304, row, &settings.beach_elevation, -5, 20, .1); row += 1
        case .Shelf:
            _ = editor_ui_slider_input(editor, layout, 305, row, &settings.shelf_depth, -80, 0, .5); row += 1
            _ = editor_ui_slider_input(editor, layout, 306, row, &settings.shelf_slope, .1, 4, .05); row += 1
        case .Ridge, .Valley, .Slope:
            _ = editor_ui_slider_input(editor, layout, 307, row, &settings.height, 1, 200, 1); row += 1
        case .Grade:
            _ = editor_ui_slider_input(editor, layout, 308, row, &settings.maximum_grade, 0, .5, .01); row += 1
            grade_mode_bounds := editor_ui_slider_bounds(layout, row)
            if pressed && canvas2d.CheckCollisionPointRec(mouse, {grade_mode_bounds.x, grade_mode_bounds.y + 20, grade_mode_bounds.width, 30}) do settings.elevation_mode = settings.elevation_mode == .Sampled ? .Explicit : .Sampled
            row += 1
            if settings.elevation_mode == .Explicit {
                _ = editor_ui_slider_input(
                    editor,
                    layout,
                    318,
                    row,
                    &settings.grade_start_elevation,
                    -50,
                    300,
                    .5,
                ); row += 1
                _ = editor_ui_slider_input(
                    editor,
                    layout,
                    319,
                    row,
                    &settings.grade_end_elevation,
                    -50,
                    300,
                    .5,
                ); row += 1
            }
        case .Relax, .Erode, .Deposit:
            iterations := f32(settings.iterations)
            if editor_ui_slider_input(editor, layout, 309, row, &iterations, 1, 96, 1) do settings.iterations = int(iterations + .5)
            row += 1
            _ = editor_ui_slider_input(editor, layout, 310, row, &settings.talus, 0, 4, .05); row += 1
        case .Roughen:
            _ = editor_ui_slider_input(editor, layout, 311, row, &settings.amplitude, 0, 40, .25); row += 1
            _ = editor_ui_slider_input(editor, layout, 312, row, &settings.noise_scale, 2, 200, 1); row += 1
        case .Terrace:
            _ = editor_ui_slider_input(editor, layout, 313, row, &settings.terrace_height, .5, 20, .5); row += 1
            _ = editor_ui_slider_input(editor, layout, 314, row, &settings.terrace_reference, -50, 200, .5); row += 1
        case .Pad, .Cut_Fill:
            _ = editor_ui_slider_input(editor, layout, 315, row, &settings.target_elevation, -50, 300, .5); row += 1
        }
        advanced_bounds := editor_ui_slider_bounds(layout, row)
        if pressed && canvas2d.CheckCollisionPointRec(mouse, {advanced_bounds.x, advanced_bounds.y + 20, advanced_bounds.width, 30}) do editor.terrain_sculpt.advanced = !editor.terrain_sculpt.advanced
        row += 1
        if editor.terrain_sculpt.advanced {
            seabed_bounds := editor_ui_slider_bounds(layout, row)
            if pressed && canvas2d.CheckCollisionPointRec(mouse, {seabed_bounds.x, seabed_bounds.y + 20, seabed_bounds.width, 30}) do settings.affect_seabed = !settings.affect_seabed
            row += 1
            _ = editor_ui_slider_input(editor, layout, 316, row, &settings.spacing, .05, 1, .01); row += 1
            _ = editor_ui_slider_input(editor, layout, 317, row, &settings.inner_core, 0, 1, .01); row += 1
            #partial switch editor.terrain_sculpt.action {
            case .Ridge, .Valley:
                profile_bounds := editor_ui_slider_bounds(layout, row)
                third := (profile_bounds.width - 8) / 3
                if pressed {
                    if canvas2d.CheckCollisionPointRec(mouse, {profile_bounds.x, profile_bounds.y + 20, third, 30}) do settings.profile = .Round
                    if canvas2d.CheckCollisionPointRec(mouse, {profile_bounds.x + third + 4, profile_bounds.y + 20, third, 30}) do settings.profile = .Sharp
                    if canvas2d.CheckCollisionPointRec(mouse, {profile_bounds.x + (third + 4) * 2, profile_bounds.y + 20, third, 30}) do settings.profile = .Cliff
                }
                row += 1
                _ = editor_ui_slider_input(editor, layout, 320, row, &settings.side_bias, -1, 1, .05); row += 1
                _ = editor_ui_slider_input(editor, layout, 321, row, &settings.roughness, 0, 20, .25); row += 1
                _ = editor_ui_slider_input(editor, layout, 322, row, &settings.endpoint_taper, 0, .5, .01); row += 1
            case .Slope:
                _ = editor_ui_slider_input(editor, layout, 323, row, &settings.side_bias, -1, 1, .05); row += 1
                _ = editor_ui_slider_input(editor, layout, 324, row, &settings.preserve_detail, 0, 1, .01); row += 1
            case .Erode:
                _ = editor_ui_slider_input(editor, layout, 325, row, &settings.rainfall, .01, 2, .01); row += 1
                _ = editor_ui_slider_input(editor, layout, 326, row, &settings.sediment, .01, 2, .01); row += 1
            case .Roughen:
                octaves := f32(settings.octaves)
                if editor_ui_slider_input(editor, layout, 327, row, &octaves, 1, 6, 1) do settings.octaves = int(octaves + .5)
                row += 1
            case .Terrace:
                _ = editor_ui_slider_input(editor, layout, 328, row, &settings.terrace_depth, 1, 50, .5); row += 1
                _ = editor_ui_slider_input(editor, layout, 329, row, &settings.retaining_slope, 0, 1, .01); row += 1
                _ = editor_ui_slider_input(editor, layout, 330, row, &settings.irregularity, 0, 1, .01); row += 1
            case .Pad:
                _ = editor_ui_slider_input(editor, layout, 331, row, &settings.edge_slope, 0, 1, .01); row += 1
                _ = editor_ui_slider_input(editor, layout, 332, row, &settings.corner_radius, 0, 50, .5); row += 1
            case .Cut_Fill:
                _ = editor_ui_slider_input(editor, layout, 333, row, &settings.cut_limit, 0, 100, 1); row += 1
                _ = editor_ui_slider_input(editor, layout, 334, row, &settings.fill_limit, 0, 100, 1); row += 1
            }
        }
    case .Smooth, .Paint:
        _ = editor_ui_slider_input(editor, layout, 1, row, &editor.radius, terrain.BASE_CELL_SIZE, 400, 1)
        row += 1
        _ = editor_ui_slider_input(editor, layout, 2, row, &editor.strength, 0, 1, .01)
        row += 1
        _ = editor_ui_slider_input(editor, layout, 3, row, &editor.hardness, 0, 1, .01)
        row += 1
    case .Formations:
        bounds := editor_ui_slider_bounds(layout, row)
        if !editor.rock_placement_mode {
            half := (bounds.width - 6) * .5
            if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 24, half, 30}) {
                editor.structure_auto_kind = true
            } else if pressed &&
               canvas2d.CheckCollisionPointRec(mouse, {bounds.x + half + 6, bounds.y + 24, half, 30}) {
                structure_cycle_kind(editor)
            }
            row += 2
        } else {
            row += 1
            material_bounds := editor_ui_slider_bounds(layout, row)
            gap := f32(5)
            third := (material_bounds.width - gap * 2) / 3
            if pressed {
                for variant in 0 ..< 3 {
                    variant_bounds := canvas2d.Rectangle {
                        material_bounds.x + f32(variant) * (third + gap),
                        material_bounds.y + 24,
                        third,
                        30,
                    }
                    if canvas2d.CheckCollisionPointRec(mouse, variant_bounds) do editor.rock_material_variant = variant
                }
            }
            row += 1
        }
        _ = editor_ui_slider_input(
            editor,
            layout,
            14,
            row,
            &editor.formation_brush_radius,
            terrain.BASE_CELL_SIZE,
            240,
            terrain.BASE_CELL_SIZE,
        )
        row += 1
        _ = editor_ui_slider_input(editor, layout, 15, row, &editor.formation_brush_strength, .02, 1, .01)
        row += 1
        _ = editor_ui_slider_input(editor, layout, 16, row, &editor.formation_brush_hardness, 0, 1, .01)
        row += 1
    case .Foliage:
        preview_bounds := editor_ui_slider_bounds(layout, row)
        preview_gap := f32(8)
        preview_width := (preview_bounds.width - preview_gap) * .5
        ground_preview := canvas2d.Rectangle{preview_bounds.x, preview_bounds.y + 24, preview_width, 70}
        climbing_preview := canvas2d.Rectangle {
            preview_bounds.x + preview_width + preview_gap,
            preview_bounds.y + 24,
            preview_width,
            70,
        }
        if pressed && canvas2d.CheckCollisionPointRec(mouse, ground_preview) {
            editor.plant_stamp_mode = .Ground
            editor.climbing_leaf_paint_mode = false
            editor.climbing_leaf_painting = false
            editor.plant_stamp_target_valid = false
        } else if pressed && canvas2d.CheckCollisionPointRec(mouse, climbing_preview) {
            editor.plant_stamp_mode = .Climbing
            editor.climbing_leaf_paint_mode = true
            editor.formation_brush_painting = false
            editor.formation_brush_group_id = 0
        }
        row += 2
        if editor.plant_stamp_mode == .Climbing {
            _ = editor_ui_slider_input(
                editor,
                layout,
                11,
                row,
                &editor.climbing_leaf_brush_radius,
                terrain.BASE_CELL_SIZE,
                240,
                terrain.BASE_CELL_SIZE,
            )
            row += 1
            _ = editor_ui_slider_input(editor, layout, 12, row, &editor.climbing_leaf_brush_strength, .02, 1, .01)
            row += 1
            break
        }
        bounds := editor_ui_slider_bounds(layout, row)
        half := (bounds.width - 6) * .5
        if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 24, half, 30}) {
            editor.foliage_hedgerow_mode = false
            editor.structure_placing = false
        } else if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x + half + 6, bounds.y + 24, half, 30}) {
            editor.foliage_hedgerow_mode = true
            editor.formation_brush_painting = false
            editor.formation_brush_group_id = 0
        }
        row += 1
        _ = editor_ui_slider_input(
            editor,
            layout,
            14,
            row,
            &editor.formation_brush_radius,
            terrain.BASE_CELL_SIZE,
            240,
            terrain.BASE_CELL_SIZE,
        )
        row += 1
        _ = editor_ui_slider_input(editor, layout, 15, row, &editor.formation_brush_strength, .02, 1, .01)
        row += 1
        _ = editor_ui_slider_input(editor, layout, 16, row, &editor.formation_brush_hardness, 0, 1, .01)
        row += 1
    case .Ridge, .Cliff:
        _ = editor_ui_slider_input(
            editor,
            layout,
            4,
            row,
            &editor.curve_width,
            terrain.BASE_CELL_SIZE,
            terrain.BASE_CELL_SIZE * 16,
            terrain.BASE_CELL_SIZE,
        )
        row += 1
        if editor.authoring_tool == .Cliff {
            bounds := editor_ui_slider_bounds(layout, row)
            gap := f32(5)
            button_width := (bounds.width - gap * 2) / 3
            if pressed {
                if canvas2d.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 24, button_width, 30}) {
                    editor.cliff_elevation_mode = .Raise
                } else if canvas2d.CheckCollisionPointRec(
                    mouse,
                    {bounds.x + button_width + gap, bounds.y + 24, button_width, 30},
                ) {
                    editor.cliff_elevation_mode = .Lower
                } else if canvas2d.CheckCollisionPointRec(
                    mouse,
                    {bounds.x + (button_width + gap) * 2, bounds.y + 24, button_width, 30},
                ) {
                    editor.cliff_elevation_mode = .Split
                }
            }
            row += 1
        }
        _ = editor_ui_slider_input(
            editor,
            layout,
            5,
            row,
            &editor.curve_height,
            terrain.BASE_CELL_SIZE,
            terrain.BASE_CELL_SIZE * 24,
            terrain.BASE_CELL_SIZE,
        )
        row += 1
    case .Building:
        bounds := editor_ui_slider_bounds(layout, row)
        half := (bounds.width - 6) * .5
        if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 24, half, 30}) {
            editor.airport_stamp_mode = false
            editor.airport_preview_valid = false
        } else if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x + half + 6, bounds.y + 24, half, 30}) {
            editor.airport_stamp_mode = true
            editor.architecture_painting = false
            architecture.city_plan_destroy(&editor.architecture_preview_plan)
        }
        row += 1
        if editor.airport_stamp_mode do break
        bounds = editor_ui_slider_bounds(layout, row)
        half = (bounds.width - 6) * .5
        if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 24, half, 30}) {
            editor.architecture_brush_shape = .Square
        } else if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x + half + 6, bounds.y + 24, half, 30}) {
            editor.architecture_brush_shape = .Rectangle
        } else if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 58, half, 30}) {
            editor.architecture_brush_shape = .Circle
        } else if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x + half + 6, bounds.y + 58, half, 30}) {
            editor.architecture_brush_shape = .Macaroni
        }
        row += 2
        bounds = editor_ui_slider_bounds(layout, row)
        third := (bounds.width - 12) / 3
        if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 24, third, 30}) {
            editor.architecture_brush_preset = .Small
        } else if pressed && canvas2d.CheckCollisionPointRec(mouse, {bounds.x + third + 6, bounds.y + 24, third, 30}) {
            editor.architecture_brush_preset = .Medium
        } else if pressed &&
           canvas2d.CheckCollisionPointRec(mouse, {bounds.x + (third + 6) * 2, bounds.y + 24, third, 30}) {
            editor.architecture_brush_preset = .Large
        }
        row += 1
        _ = editor_ui_slider_input(editor, layout, 7, row, &editor.architecture_brush_strength, .02, 1, .01)
        row += 1
        _ = editor_ui_slider_input(editor, layout, 10, row, &editor.architecture_brush_hardness, 0, 1, .01)
        row += 1
    case .Marina:
        // The footprint is fixed by the real-size marina design.
        row += 0
    case .Farm:
        previous_radius := editor.farm_brush_radius
        _ = editor_ui_slider_input(editor, layout, 14, row, &editor.farm_brush_radius, 20, 120, 2.5)
        if editor.farm_brush_radius != previous_radius {
            editor.farm_preview_revision = 0
            editor.farm_preview_valid = false
        }
        row += 1
    case .Wreck:
        previous_size := editor.wreck_brush_size
        _ = editor_ui_slider_input(editor, layout, 15, row, &editor.wreck_brush_size, 160, 520, 10)
        if editor.wreck_brush_size != previous_size {
            editor.wreck_preview_revision = 0
            editor.wreck_preview_valid = false
        }
        row += 1
    case .ClimbingLeaves:
        _ = editor_ui_slider_input(
            editor,
            layout,
            11,
            row,
            &editor.climbing_leaf_brush_radius,
            terrain.BASE_CELL_SIZE,
            240,
            terrain.BASE_CELL_SIZE,
        )
        row += 1
        _ = editor_ui_slider_input(editor, layout, 12, row, &editor.climbing_leaf_brush_strength, .02, 1, .01)
        row += 1
        _ = editor_ui_slider_input(editor, layout, 13, row, &editor.climbing_leaf_brush_hardness, 0, 1, .01)
        row += 1
    case .Roads:
        mode_bounds := editor_ui_slider_bounds(layout, row)
        if pressed && canvas2d.CheckCollisionPointRec(mouse, mode_bounds) {
            switch editor.road_construction_mode {
            case .Straight:
                editor.road_construction_mode = .Terrain_Route
            case .Terrain_Route:
                editor.road_construction_mode = .Authored_Curve
            case .Authored_Curve:
                editor.road_construction_mode = .Straight
            }
            editor.road_construction_phase = editor.road_selected_node >= 0 ? .Choose_End : .Idle
            editor.road_preview_control_from = {}
            editor.road_preview_control_to = {}
            road_preview_clear(editor)
        }
        row += 1
        surface_bounds := editor_ui_slider_bounds(layout, row)
        if pressed && canvas2d.CheckCollisionPointRec(mouse, surface_bounds) {
            road_cycle_pavement(editor)
        }
        row += 1
        road_changed := editor_ui_slider_input(
            editor,
            layout,
            8,
            row,
            &editor.road_width,
            2.5,
            24,
            .5,
            editor.road_selected_node >= 0 ? 2 : 0,
        )
        if road_changed && editor.road_selected_node >= 0 {
            for &edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
                if edge.from == editor.road_selected_node || edge.to == editor.road_selected_node {
                    edge.half_width = editor.road_width * .5
                }
            }
            editor.project.revision += 1
        }
        row += 1
        shoulder_changed := editor_ui_slider_input(
            editor,
            layout,
            9,
            row,
            &editor.road_shoulder_width,
            0,
            8,
            .25,
            editor.road_selected_node >= 0 ? 2 : 0,
        )
        if shoulder_changed && editor.road_selected_node >= 0 {
            for &edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
                if edge.from == editor.road_selected_node || edge.to == editor.road_selected_node {
                    edge.shoulder_width = editor.road_shoulder_width
                }
            }
            editor.project.revision += 1
        }
        row += 1
        if editor.road_construction_mode == .Terrain_Route {
            alternatives := editor_ui_slider_bounds(layout, row)
            gap := f32(3)
            button_width := (alternatives.width - gap * 3) / 4
            for index in 0 ..< 4 {
                candidate_bounds := canvas2d.Rectangle {
                    alternatives.x + f32(index) * (button_width + gap),
                    alternatives.y,
                    button_width,
                    25,
                }
                if pressed && canvas2d.CheckCollisionPointRec(mouse, candidate_bounds) {
                    editor.road_design_alternative = road_designer.Named_Alternative(index)
                    _ = road_design_preview_step(editor)
                }
            }
            row += 1
            if editor.road_design_optimizer != nil {
                if pressed && canvas2d.CheckCollisionPointRec(mouse, editor_ui_slider_bounds(layout, row)) {
                    editor.road_design_paused = !editor.road_design_paused
                }
                row += 1
                _, selected_ok := road_designer.candidate(editor.road_design_optimizer, editor.road_design_alternative)
                if selected_ok do row += 1
            }
        }
        bounds := editor_ui_slider_bounds(layout, row)
        gap := f32(4)
        button_width := (bounds.width - gap * 2) / 3
        for index in 0 ..< 6 {
            column, toggle_row := index % 3, index / 3
            candidate := canvas2d.Rectangle {
                bounds.x + f32(column) * (button_width + gap),
                bounds.y + f32(toggle_row) * 23,
                button_width,
                20,
            }
            if pressed && canvas2d.CheckCollisionPointRec(mouse, candidate) {
                switch index {
                case 0:
                    editor.road_snap_nodes = !editor.road_snap_nodes
                case 1:
                    editor.road_snap_edges = !editor.road_snap_edges
                case 2:
                    editor.road_snap_grid = !editor.road_snap_grid
                case 3:
                    editor.road_snap_angles = !editor.road_snap_angles
                case 4:
                    editor.road_snap_tangents = !editor.road_snap_tangents
                case 5:
                    editor.road_snap_perpendiculars = !editor.road_snap_perpendiculars
                }
                editor.road_preview_cell_valid = false
            }
        }
        row += 1
        if editor.road_selected_node >= 0 && editor.road_selected_node < editor.project.road_graph.node_count {
            node := &editor.project.road_graph.nodes[editor.road_selected_node]
            if editor_ui_slider_input(editor, layout, 10, row, &node.junction_radius, 1, 40, .5, 2) {
                editor.project.revision += 1
            }
            row += 1
            if editor.road_construction_mode == .Terrain_Route &&
               roads.node_degree(&editor.project.road_graph, editor.road_selected_node) == 2 {
                if pressed && canvas2d.CheckCollisionPointRec(mouse, editor_ui_slider_bounds(layout, row)) {
                    _ = road_design_redesign_selected_chain(editor)
                }
                row += 1
            }
        }
    case .GreekAssets:
        region_bounds := editor_ui_slider_bounds(layout, row)
        if pressed && canvas2d.CheckCollisionPointRec(mouse, region_bounds) {
            editor.ruin_stamp_aegean = !editor.ruin_stamp_aegean
            editor.ruin_stamp_preview_valid = false
        }
        row += 1
        mode_bounds := editor_ui_slider_bounds(layout, row)
        if pressed && canvas2d.CheckCollisionPointRec(mouse, mode_bounds) {
            editor.ruin_stamp_complex = !editor.ruin_stamp_complex
            editor.ruin_stamp_preview_valid = false
        }
        row += 2
    case .Obstacles:
        actions := editor_ui_slider_bounds(layout, row)
        half := (actions.width - 6) * .5
        if pressed && canvas2d.CheckCollisionPointRec(mouse, {actions.x, actions.y + 8, half, 30}) {
            _ = sdf_obstacle_add(editor)
            return
        }
        if pressed && canvas2d.CheckCollisionPointRec(mouse, {actions.x + half + 6, actions.y + 8, half, 30}) {
            if sdf_obstacle_delete_selected(editor) do return
        }
        row += 1
        list_bounds := editor_ui_slider_bounds(layout, row)
        previous_bounds := canvas2d.Rectangle{list_bounds.x + list_bounds.width - 66, list_bounds.y - 4, 30, 26}
        next_bounds := canvas2d.Rectangle{list_bounds.x + list_bounds.width - 30, list_bounds.y - 4, 30, 26}
        if pressed && canvas2d.CheckCollisionPointRec(mouse, previous_bounds) {
            sdf_obstacle_scroll(editor, -1)
            return
        }
        if pressed && canvas2d.CheckCollisionPointRec(mouse, next_bounds) {
            sdf_obstacle_scroll(editor, 1)
            return
        }
        row += 1
        sdf_obstacle_list_scroll_clamp(editor)
        first := editor.sdf_obstacle_interaction.list_scroll
        visible := min(SDF_OBSTACLE_LIST_VISIBLE_COUNT, editor.sdf_obstacle_count - first)
        for item in 0 ..< visible {
            index := first + item
            if pressed && canvas2d.CheckCollisionPointRec(mouse, editor_ui_slider_bounds(layout, row + item)) {
                _ = sdf_obstacle_select(editor, index)
                return
            }
        }
        row += max(visible, 1)
    }

    if pressed {
        if canvas2d.CheckCollisionPointRec(mouse, editor_ui_small_action_bounds(layout, 0)) {
            map_editor_save(editor)
        } else if canvas2d.CheckCollisionPointRec(mouse, editor_ui_small_action_bounds(layout, 1)) {
            map_editor_load(editor)
        } else if canvas2d.CheckCollisionPointRec(mouse, editor_ui_small_action_bounds(layout, 2)) {
            terrain_panel_undo(editor)
        } else if canvas2d.CheckCollisionPointRec(mouse, editor_ui_small_action_bounds(layout, 3)) {
            terrain_panel_redo(editor)
        }
    }
}
