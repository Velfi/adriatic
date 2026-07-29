package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import farmland "../packages/farmland"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:fmt"
import "core:math"
import rl "zelda_engine:canvas2d"

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
}

AUTHORING_TOOL_COUNT :: 14
EDITOR_UI_TOP_HEIGHT :: f32(54)
EDITOR_UI_RAIL_WIDTH :: f32(184)
EDITOR_UI_INSPECTOR_WIDTH :: f32(292)
EDITOR_UI_GUTTER :: f32(12)
EDITOR_UI_BUTTON_TEXT_Y_OFFSET :: f32(3)

Editor_UI_State :: struct {
    left_collapsed:      bool,
    inspector_collapsed: bool,
    active_slider:       int,
    debug_key_down:      bool,
}

Editor_UI_Layout :: struct {
    top:               rl.Rectangle,
    left:              rl.Rectangle,
    inspector:         rl.Rectangle,
    hint:              rl.Rectangle,
    left_toggle:       rl.Rectangle,
    inspector_toggle:  rl.Rectangle,
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
        return "FOLIAGE"
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
        return "CLIMBING LEAVES"
    case .Roads:
        return "ROADS"
    case .GreekAssets:
        return "GREEK ASSETS"
    }
    return "TOOL"
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
    }
    return ""
}

authoring_select_tool :: proc(editor: ^Editor, selected: Authoring_Tool) {
    if editor == nil do return
    editor.authoring_tool = selected
    editor.architecture_painting = false
    architecture.city_plan_destroy(&editor.architecture_preview_plan)
    editor.architecture_dirty_bounds = {}
    editor.architecture_node_mode = false
    editor.architecture_paint_mode = false
    editor.marina_paint_mode = false
    editor.marina_preview_valid = false
    editor.farm_paint_mode = false
    editor.wreck_paint_mode = false
    editor.climbing_leaf_paint_mode = false
    editor.climbing_leaf_painting = false
    editor.formation_brush_painting = false
    editor.formation_brush_group_id = 0
    editor.greek_placement_mode = false
    editor.road_mode = false
    editor.curve_mode = false
    switch selected {
    case .Sculpt:
        editor.tool = .Raise
    case .Smooth:
        editor.tool = .Smooth
    case .Paint:
        editor.tool = .Paint
    case .Formations:
        editor.tool = .Structure
    case .Foliage:
        editor.tool = .Structure
    case .Ridge:
        editor.tool = .Structure
        editor.curve_mode = true
        editor.curve_cliff_mode = false
    case .Cliff:
        editor.tool = .Structure
        editor.curve_mode = true
        editor.curve_cliff_mode = true
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
        editor.tool = .Structure
        editor.climbing_leaf_paint_mode = true
    case .Roads:
        editor.tool = .Structure
        editor.road_mode = true
        editor.structure_selected = -1
    case .GreekAssets:
        editor.tool = .Structure
        editor.greek_placement_mode = true
        editor.structure_selected = -1
    }
    editor.tweak.terrain.tool = editor.tool
    curve_reset(editor)
    editor.structure_placing = false
    editor.structure_moving = false
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
editor_ui_tool_bounds :: #force_inline proc(layout: Editor_UI_Layout, index: int) -> rl.Rectangle {
    return {layout.left.x + 10, layout.left.y + 50 + f32(index) * 39, layout.left.width - 20, 35}
}

@(no_instrumentation)
editor_ui_focus_bounds :: #force_inline proc(layout: Editor_UI_Layout) -> rl.Rectangle {
    return {layout.left.x + 10, layout.left.y + layout.left.height - 88, layout.left.width - 20, 32}
}

@(no_instrumentation)
editor_ui_spawn_bounds :: #force_inline proc(layout: Editor_UI_Layout) -> rl.Rectangle {
    return {layout.left.x + 10, layout.left.y + layout.left.height - 46, layout.left.width - 20, 36}
}

editor_ui_panel_button :: proc(bounds: rl.Rectangle, label: cstring, selected: bool = false, enabled: bool = true) {
    hovered := enabled && rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    fill := rl.Color{35, 39, 46, 246}
    border := rl.Color{73, 81, 92, 255}
    text := rl.Color{226, 231, 236, 255}
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
    rl.DrawRectangleRounded(bounds, .12, 6, fill)
    rl.DrawRectangleRoundedLinesEx(bounds, .12, 6, selected ? 2 : 1, border)
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
    rl.DrawLineEx({x, y + 22}, {x + width, y + 22}, 1, {58, 65, 74, 255})
}

@(no_instrumentation)
editor_ui_slider_bounds :: #force_inline proc(layout: Editor_UI_Layout, row: int) -> rl.Rectangle {
    return {layout.inspector.x + 14, layout.inspector.y + 82 + f32(row) * 48, layout.inspector.width - 28, 42}
}

editor_ui_slider_draw :: proc(bounds: rl.Rectangle, label: cstring, value, minimum, maximum: f32, decimals: int = 1) {
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
    track := rl.Rectangle{bounds.x, bounds.y + 27, bounds.width, 6}
    rl.DrawRectangleRounded(track, 1, 4, {50, 56, 64, 255})
    rl.DrawRectangleRounded({track.x, track.y, track.width * normalized, track.height}, 1, 4, {60, 164, 157, 255})
    rl.DrawCircleV({track.x + track.width * normalized, track.y + 3}, 6, {221, 238, 237, 255})
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
    mouse := rl.GetMousePosition()
    if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse, bounds) {
        editor.editor_ui.active_slider = slider_id
        if history == 1 {
            terrain_history_push_undo(editor)
        } else if history == 2 {
            structure_history_push_undo(editor)
        }
    }
    if editor.editor_ui.active_slider != slider_id do return false
    if rl.IsMouseButtonReleased(.LEFT) {
        editor.editor_ui.active_slider = 0
        return false
    }
    if !rl.IsMouseButtonDown(.LEFT) do return false
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
editor_ui_small_action_bounds :: #force_inline proc(layout: Editor_UI_Layout, index: int) -> rl.Rectangle {
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
        if editor.road_drag_edge >= 0 do return "Drag the control handle to shape the road; release to commit."
        if editor.road_selected_node >= 0 do return "Extend or connect the selected node; right-click to end the chain."
        return "Click terrain to start a road; click a node to connect or branch."
    }
    if editor.architecture_paint_mode do return "Drag to orient one settlement piece; release to stamp. Right-drag erases."
    if editor.curve_drawing do return editor.curve_cliff_mode ? "Draw the cliff path; release to commit." : "Draw the ridge path; release to commit."
    if editor.formation_brush_painting do return "Release to commit the brush stroke."
    if editor.structure_placing do return "Drag the footprint; wheel zooms; Shift changes size; Alt changes height."
    if editor.structure_moving do return "Move the selected formation; release to commit."
    switch editor.authoring_tool {
    case .Sculpt:
        return "Left raises terrain; right lowers it. Wheel zooms; use Radius in the inspector."
    case .Smooth:
        return "Paint smoothing with either mouse button. Wheel zooms; use Radius in the inspector."
    case .Paint:
        return "Left paints material; right erases it. Wheel zooms; use Radius in the inspector."
    case .Formations:
        return "Left stamps formations; right erases. Wheel zooms; Shift density; Alt hardness."
    case .Foliage:
        if editor.foliage_hedgerow_mode {
            return "Drag a cheap hedgerow. Radius controls its width and height."
        }
        return "Left stamps foliage; right erases. Wheel zooms; Shift density; Alt hardness."
    case .Ridge:
        return "Draw a freehand ridge. Wheel zooms; Shift adjusts width and height."
    case .Cliff:
        return "Draw a freehand cliff. Wheel zooms; Shift adjusts width and height."
    case .Building:
        return "Choose a shape and preset, then drag to orient it. Left adds; right erases."
    case .Marina:
        return "Left places a complete shoreline-oriented marina; right removes it."
    case .Farm:
        return "Left places the previewed farm; right generates a new seed."
    case .Wreck:
        return "Left places the previewed wreck; right generates a new seed."
    case .ClimbingLeaves:
        return "Left spreads climbing leaves; right erases. Wheel zooms; Shift spread; Alt hardness."
    case .Roads:
        return "Click terrain to add nodes and drag handles to curve edges."
    case .GreekAssets:
        return "Click an asset, then click terrain to place it. Wheel zooms; Alt rotates; Shift scales."
    }
    return ""
}

editor_ui_draw_left :: proc(editor: ^Editor, layout: Editor_UI_Layout) {
    if !layout.left_visible {
        editor_ui_panel_button(layout.left_toggle, ">>")
        return
    }
    rl.DrawRectangleRounded(layout.left, .025, 6, {25, 28, 33, 248})
    rl.DrawRectangleRoundedLinesEx(layout.left, .025, 6, 1, {62, 69, 78, 255})
    ui_draw_text(.Heading, "TOOLS", {layout.left.x + 12, layout.left.y + 14}, .5, {235, 239, 243, 255})
    editor_ui_panel_button({layout.left.x + layout.left.width - 39, layout.left.y + 10, 29, 28}, "<<")
    for index in 0 ..< AUTHORING_TOOL_COUNT {
        tool := Authoring_Tool(index)
        bounds := editor_ui_tool_bounds(layout, index)
        selected := editor.authoring_tool == tool
        hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
        fill := selected ? rl.Color{35, 91, 94, 255} : rl.Color{35, 39, 46, 246}
        if hovered && !selected do fill = {48, 55, 64, 250}
        border := selected ? rl.Color{82, 207, 198, 255} : rl.Color{66, 74, 84, 255}
        rl.DrawRectangleRounded(bounds, .10, 6, fill)
        rl.DrawRectangleRoundedLinesEx(bounds, .10, 6, selected ? 2 : 1, border)
        ui_draw_text(.Label, authoring_tool_name(tool), {bounds.x + 12, bounds.y + 12}, .2, {235, 239, 243, 255})
        shortcut := authoring_tool_shortcut(tool)
        shortcut_size := ui_measure_text(.Data, shortcut, 0)
        ui_draw_text(
            .Data,
            shortcut,
            {bounds.x + bounds.width - shortcut_size.x - 10, bounds.y + 12},
            0,
            {139, 149, 160, 255},
        )
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
    rl.DrawRectangleRounded(panel, .025, 6, {25, 28, 33, 248})
    rl.DrawRectangleRoundedLinesEx(panel, .025, 6, 1, {62, 69, 78, 255})
    ui_draw_text(
        .Heading,
        authoring_tool_name(editor.authoring_tool),
        {panel.x + 14, panel.y + 14},
        .5,
        {235, 239, 243, 255},
    )
    editor_ui_panel_button({panel.x + panel.width - 39, panel.y + 10, 29, 28}, ">>")
    editor_ui_section_title("TOOL SETTINGS", panel.x + 14, panel.y + 50, panel.width - 28)

    row := 0
    switch editor.authoring_tool {
    case .Sculpt, .Smooth, .Paint:
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
        profile := editor.structure_auto_kind ? "AUTOMATIC" : formation_kind_name(editor.structure_kind)
        ui_draw_text(.Label, "PROFILE", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        profile_size := ui_measure_text(.Data, profile, .5)
        ui_draw_text(.Data, profile, {bounds.x + bounds.width - profile_size.x, bounds.y}, .5, {134, 224, 216, 255})
        half := (bounds.width - 6) * .5
        editor_ui_panel_button({bounds.x, bounds.y + 24, half, 30}, "AUTO", editor.structure_auto_kind)
        editor_ui_panel_button(
            {bounds.x + half + 6, bounds.y + 24, half, 30},
            "CYCLE  [V]",
            !editor.structure_auto_kind,
        )
        row += 2
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
                "DRAG TO PLACE FORMATIONS",
                {panel.x + 14, panel.y + 82 + f32(row) * 48},
                .4,
                {139, 149, 160, 255},
            )
        }
    case .Foliage:
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
        ui_draw_text(.Label, "SHAPE", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        editor_ui_panel_button({bounds.x, bounds.y + 24, half, 30}, "SQUARE", editor.architecture_brush_shape == .Square)
        editor_ui_panel_button({bounds.x + half + 6, bounds.y + 24, half, 30}, "RECTANGLE", editor.architecture_brush_shape == .Rectangle)
        editor_ui_panel_button({bounds.x, bounds.y + 58, half, 30}, "CIRCLE", editor.architecture_brush_shape == .Circle)
        editor_ui_panel_button({bounds.x + half + 6, bounds.y + 58, half, 30}, "MACARONI", editor.architecture_brush_shape == .Macaroni)
        row += 2
        bounds = editor_ui_slider_bounds(layout, row)
        third := (bounds.width - 12) / 3
        ui_draw_text(.Label, "PRESET", {bounds.x, bounds.y}, .5, {209, 215, 222, 255})
        editor_ui_panel_button({bounds.x, bounds.y + 24, third, 30}, "SMALL", editor.architecture_brush_preset == .Small)
        editor_ui_panel_button({bounds.x + third + 6, bounds.y + 24, third, 30}, "MEDIUM", editor.architecture_brush_preset == .Medium)
        editor_ui_panel_button({bounds.x + (third + 6) * 2, bounds.y + 24, third, 30}, "LARGE", editor.architecture_brush_preset == .Large)
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
        preview_color := editor.marina_preview_valid ? rl.Color{134, 224, 216, 255} : rl.Color{224, 126, 108, 255}
        ui_draw_text(.Data, preview_label, {bounds.x, bounds.y + 38}, .4, preview_color)
        score_color := rl.Color{231, 150, 126, 255}
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
        preview_color := editor.wreck_preview_valid ? rl.Color{134, 224, 216, 255} : rl.Color{224, 126, 108, 255}
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
        preview_label: cstring = editor.farm_preview_valid ? "CLICK TO PLACE BEST CANDIDATE" : "NO SUITABLE CANDIDATE"
        preview_color := editor.farm_preview_valid ? rl.Color{134, 224, 216, 255} : rl.Color{224, 126, 108, 255}
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
    case .GreekAssets:
        bounds := editor_ui_slider_bounds(layout, row)
        ui_draw_text(
            .Data,
            editor.greek_assets[editor.greek_asset_selected].name,
            {bounds.x, bounds.y},
            .45,
            {134, 224, 216, 255},
        )
        row += 1
        asset_list_y := panel.y + 132
        for index in 0 ..< GREEK_ASSET_CAPACITY {
            asset_bounds := rl.Rectangle{panel.x + 14, asset_list_y + f32(index) * 34, panel.width - 28, 28}
            editor_ui_panel_button(
                asset_bounds,
                editor.greek_assets[index].name,
                editor.greek_asset_selected == index,
                editor.greek_assets[index].ready,
            )
        }
        ui_draw_text(
            .Data,
            fmt.ctprintf(
                "ROTATION %3.0f°   SCALE %.2f   PLACED %d",
                editor.greek_asset_rotation * 180 / math.PI,
                editor.greek_asset_scale,
                editor.greek_placement_count,
            ),
            {panel.x + 14, asset_list_y + f32(GREEK_ASSET_CAPACITY) * 34 + 10},
            .4,
            {209, 215, 222, 255},
        )
        row = 7
    case .Roads:
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
        if editor.road_selected_node >= 0 && editor.road_selected_node < editor.project.road_graph.node_count {
            radius := editor.project.road_graph.nodes[editor.road_selected_node].junction_radius
            editor_ui_slider_draw(editor_ui_slider_bounds(layout, row), "JUNCTION RADIUS", radius, 1, 40, 1)
            row += 1
        }
    }

    world_y := min(panel.y + 82 + f32(max(row, 3)) * 48 + 12, panel.y + panel.height - 276)
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
        ui_draw_text(.Data, "CURSOR   OUTSIDE TERRAIN", {panel.x + 14, data_y}, .4, {139, 149, 160, 255})
    }
    minutes := int(editor.atmosphere.world_minutes)
    ui_draw_text(
        .Data,
        fmt.ctprintf(
            "TIME     %02d:%02d   %s",
            minutes / 60,
            minutes % 60,
            atmosphere.preset_name(editor.atmosphere.override),
        ),
        {panel.x + 14, data_y + 48},
        .4,
        {209, 215, 222, 255},
    )
    ui_draw_text(
        .Data,
        fmt.ctprintf(
            "OBJECTS  %d forms   %d roads",
            editor.project.structure_count,
            editor.project.road_graph.edge_count,
        ),
        {panel.x + 14, data_y + 72},
        .4,
        {209, 215, 222, 255},
    )
    sea_bounds := rl.Rectangle{panel.x + 14, data_y + 98, panel.width - 28, 42}
    editor_ui_slider_draw(sea_bounds, "SEA LEVEL (m)", editor.project.sea_level, -50, 50, 1)

    undo_enabled := editor.tool == .Structure ? editor.structure_undo_count > 0 : editor.terrain_undo_count > 0
    redo_enabled := editor.tool == .Structure ? editor.structure_redo_count > 0 : editor.terrain_redo_count > 0
    editor_ui_panel_button(editor_ui_small_action_bounds(layout, 0), "SAVE", false, true)
    editor_ui_panel_button(editor_ui_small_action_bounds(layout, 1), "LOAD", false, true)
    editor_ui_panel_button(editor_ui_small_action_bounds(layout, 2), "UNDO", false, undo_enabled)
    editor_ui_panel_button(editor_ui_small_action_bounds(layout, 3), "REDO", false, redo_enabled)
}

editor_ui_draw :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil do return
    layout := editor_ui_layout(editor, width, height)
    rl.DrawRectangle(0, 0, width, i32(EDITOR_UI_TOP_HEIGHT), {22, 25, 29, 248})
    rl.DrawLineEx({0, EDITOR_UI_TOP_HEIGHT - 1}, {f32(width), EDITOR_UI_TOP_HEIGHT - 1}, 1, {65, 72, 81, 255})
    project_state: cstring = editor.project.revision == editor.terrain_saved_revision ? "SAVED" : "UNSAVED"
    status := fmt.ctprintf("%s", project_state)
    status_size := ui_measure_text(.Data, status, .4)
    ui_draw_text(.Data, status, {f32(width) - status_size.x - 16, 18}, .4, {151, 161, 172, 255})
    editor_ui_draw_left(editor, layout)
    editor_ui_draw_inspector(editor, layout)
    if layout.hint.width > 160 {
        rl.DrawRectangleRounded(layout.hint, .15, 6, {25, 28, 33, 238})
        hint := editor_ui_context_message(editor)
        ui_draw_text(.Data, hint, {layout.hint.x + 12, layout.hint.y + 7}, .3, {214, 220, 226, 255})
    }
}

editor_ui_hit :: proc(editor: ^Editor, position: rl.Vector2, width, height: i32) -> bool {
    if editor == nil || editor.in_map do return imgui_captures_mouse()
    layout := editor_ui_layout(editor, width, height)
    if rl.CheckCollisionPointRec(position, layout.top) do return true
    if layout.left_visible && rl.CheckCollisionPointRec(position, layout.left) do return true
    if layout.inspector_visible && rl.CheckCollisionPointRec(position, layout.inspector) do return true
    if !layout.left_visible && rl.CheckCollisionPointRec(position, layout.left_toggle) do return true
    if !layout.inspector_visible && rl.CheckCollisionPointRec(position, layout.inspector_toggle) do return true
    if layout.hint.width > 160 && rl.CheckCollisionPointRec(position, layout.hint) do return true
    return imgui_captures_mouse()
}

editor_ui_process_input :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil || editor.in_map do return
    layout := editor_ui_layout(editor, width, height)
    mouse := rl.GetMousePosition()
    pressed := rl.IsMouseButtonPressed(.LEFT)

    if pressed {
        if layout.left_visible {
            collapse := rl.Rectangle{layout.left.x + layout.left.width - 39, layout.left.y + 10, 29, 28}
            if rl.CheckCollisionPointRec(mouse, collapse) {
                editor.editor_ui.left_collapsed = true
                return
            }
            for index in 0 ..< AUTHORING_TOOL_COUNT {
                if rl.CheckCollisionPointRec(mouse, editor_ui_tool_bounds(layout, index)) {
                    authoring_select_tool(editor, Authoring_Tool(index))
                    return
                }
            }
            if rl.CheckCollisionPointRec(mouse, editor_ui_focus_bounds(layout)) {
                editor_focus_terrain(editor)
                return
            }
            if rl.CheckCollisionPointRec(mouse, editor_ui_spawn_bounds(layout)) {
                editor_spawn_into_world(editor)
                return
            }
        } else if rl.CheckCollisionPointRec(mouse, layout.left_toggle) {
            editor.editor_ui.left_collapsed = false
            return
        }
        if layout.inspector_visible {
            collapse := rl.Rectangle{layout.inspector.x + layout.inspector.width - 39, layout.inspector.y + 10, 29, 28}
            if rl.CheckCollisionPointRec(mouse, collapse) {
                editor.editor_ui.inspector_collapsed = true
                return
            }
        } else if rl.CheckCollisionPointRec(mouse, layout.inspector_toggle) {
            editor.editor_ui.inspector_collapsed = false
            return
        }
    }

    if !layout.inspector_visible do return
    row := 0
    switch editor.authoring_tool {
    case .Sculpt, .Smooth, .Paint:
        _ = editor_ui_slider_input(editor, layout, 1, row, &editor.radius, terrain.BASE_CELL_SIZE, 400, 1)
        row += 1
        _ = editor_ui_slider_input(editor, layout, 2, row, &editor.strength, 0, 1, .01)
        row += 1
        _ = editor_ui_slider_input(editor, layout, 3, row, &editor.hardness, 0, 1, .01)
        row += 1
    case .Formations:
        bounds := editor_ui_slider_bounds(layout, row)
        half := (bounds.width - 6) * .5
        if pressed && rl.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 24, half, 30}) {
            editor.structure_auto_kind = true
        } else if pressed && rl.CheckCollisionPointRec(mouse, {bounds.x + half + 6, bounds.y + 24, half, 30}) {
            structure_cycle_kind(editor)
        }
        row += 2
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
        bounds := editor_ui_slider_bounds(layout, row)
        half := (bounds.width - 6) * .5
        if pressed && rl.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 24, half, 30}) {
            editor.foliage_hedgerow_mode = false
            editor.structure_placing = false
        } else if pressed && rl.CheckCollisionPointRec(mouse, {bounds.x + half + 6, bounds.y + 24, half, 30}) {
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
        if pressed && rl.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 24, half, 30}) {
            editor.architecture_brush_shape = .Square
        } else if pressed && rl.CheckCollisionPointRec(mouse, {bounds.x + half + 6, bounds.y + 24, half, 30}) {
            editor.architecture_brush_shape = .Rectangle
        } else if pressed && rl.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 58, half, 30}) {
            editor.architecture_brush_shape = .Circle
        } else if pressed && rl.CheckCollisionPointRec(mouse, {bounds.x + half + 6, bounds.y + 58, half, 30}) {
            editor.architecture_brush_shape = .Macaroni
        }
        row += 2
        bounds = editor_ui_slider_bounds(layout, row)
        third := (bounds.width - 12) / 3
        if pressed && rl.CheckCollisionPointRec(mouse, {bounds.x, bounds.y + 24, third, 30}) {
            editor.architecture_brush_preset = .Small
        } else if pressed && rl.CheckCollisionPointRec(mouse, {bounds.x + third + 6, bounds.y + 24, third, 30}) {
            editor.architecture_brush_preset = .Medium
        } else if pressed &&
                  rl.CheckCollisionPointRec(mouse, {bounds.x + (third + 6) * 2, bounds.y + 24, third, 30}) {
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
    case .GreekAssets:
        if pressed {
            asset_list_y := layout.inspector.y + 132
            for index in 0 ..< GREEK_ASSET_CAPACITY {
                asset_bounds := rl.Rectangle {
                    layout.inspector.x + 14,
                    asset_list_y + f32(index) * 34,
                    layout.inspector.width - 28,
                    28,
                }
                if rl.CheckCollisionPointRec(mouse, asset_bounds) && editor.greek_assets[index].ready {
                    editor.greek_asset_selected = index
                    editor.greek_asset_rotation = 0
                    editor.greek_asset_scale = 1
                    return
                }
            }
        }
        row = 7
    case .Roads:
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
        if editor.road_selected_node >= 0 && editor.road_selected_node < editor.project.road_graph.node_count {
            node := &editor.project.road_graph.nodes[editor.road_selected_node]
            if editor_ui_slider_input(editor, layout, 10, row, &node.junction_radius, 1, 40, .5, 2) {
                editor.project.revision += 1
            }
            row += 1
        }
    }

    world_y := min(
        layout.inspector.y + 82 + f32(max(row, 3)) * 48 + 12,
        layout.inspector.y + layout.inspector.height - 276,
    )
    sea_bounds := rl.Rectangle{layout.inspector.x + 14, world_y + 32 + 122, layout.inspector.width - 28, 42}
    if pressed && rl.CheckCollisionPointRec(mouse, sea_bounds) {
        editor.editor_ui.active_slider = 11
        terrain_history_push_undo(editor)
    }
    if editor.editor_ui.active_slider == 11 {
        if rl.IsMouseButtonReleased(.LEFT) {
            editor.editor_ui.active_slider = 0
        } else if rl.IsMouseButtonDown(.LEFT) {
            normalized := clamp((mouse.x - sea_bounds.x) / sea_bounds.width, 0, 1)
            editor.project.sea_level = f32(int((-50 + normalized * 100) * 10 + .5)) / 10
            editor.project.revision += 1
        }
    }

    if pressed {
        if rl.CheckCollisionPointRec(mouse, editor_ui_small_action_bounds(layout, 0)) {
            terrain_project_save(editor)
        } else if rl.CheckCollisionPointRec(mouse, editor_ui_small_action_bounds(layout, 1)) {
            terrain_project_load(editor)
        } else if rl.CheckCollisionPointRec(mouse, editor_ui_small_action_bounds(layout, 2)) {
            terrain_panel_undo(editor)
        } else if rl.CheckCollisionPointRec(mouse, editor_ui_small_action_bounds(layout, 3)) {
            terrain_panel_redo(editor)
        }
    }
}
