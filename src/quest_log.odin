package main

import quest "../packages/quest"
import story "../packages/story"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"
import game_input "zelda_engine:game_input"

Quest_Log_Tab :: enum {
    Active,
    Completed,
}

QUEST_LOG_MAX_ITEMS :: quest.MAX_NODES
QUEST_LOG_ROW_HEIGHT :: f32(58)

Quest_Log_Layout :: struct {
    panel:        canvas2d.Rectangle,
    header:       canvas2d.Rectangle,
    tabs:         canvas2d.Rectangle,
    list:         canvas2d.Rectangle,
    detail:       canvas2d.Rectangle,
    track_button: canvas2d.Rectangle,
}

quest_log_layout :: proc(width, height: i32) -> Quest_Log_Layout {
    margin := f32(16)
    panel_width := min(f32(width) - margin * 2, f32(1100))
    panel_height := min(f32(height) - margin * 2, f32(650))
    panel := canvas2d.Rectangle {
        (f32(width) - panel_width) * .5,
        (f32(height) - panel_height) * .5,
        panel_width,
        panel_height,
    }
    header_height := min(f32(104), panel.height * .22)
    gap := f32(18)
    content_y := panel.y + header_height
    content_height := panel.height - header_height - 24
    left_width := clamp(panel.width * .39, 260, 410)
    tabs := canvas2d.Rectangle{panel.x + 24, content_y, left_width, 42}
    list := canvas2d.Rectangle{tabs.x, tabs.y + tabs.height + 10, left_width, max(content_height - 52, f32(80))}
    detail := canvas2d.Rectangle {
        list.x + list.width + gap,
        content_y,
        panel.x + panel.width - 24 - (list.x + list.width + gap),
        content_height,
    }
    track_button := canvas2d.Rectangle {
        detail.x + 24,
        detail.y + detail.height - 58,
        max(detail.width - 48, f32(80)),
        40,
    }
    return {
        panel = panel,
        header = {panel.x, panel.y, panel.width, header_height},
        tabs = tabs,
        list = list,
        detail = detail,
        track_button = track_button,
    }
}

quest_log_tab_bounds :: proc(layout: Quest_Log_Layout, tab: Quest_Log_Tab) -> canvas2d.Rectangle {
    width := (layout.tabs.width - 8) * .5
    return {layout.tabs.x + f32(int(tab)) * (width + 8), layout.tabs.y, width, layout.tabs.height}
}

quest_log_row_bounds :: proc(layout: Quest_Log_Layout, visible_row: int) -> canvas2d.Rectangle {
    return {
        layout.list.x,
        layout.list.y + f32(visible_row) * QUEST_LOG_ROW_HEIGHT,
        layout.list.width,
        QUEST_LOG_ROW_HEIGHT - 6,
    }
}

quest_log_collect :: proc(editor: ^Editor, tab: Quest_Log_Tab, items: ^[QUEST_LOG_MAX_ITEMS]quest.Node_ID) -> int {
    if editor == nil || items == nil do return 0
    definition := &editor.story_quest_catalog.definition
    count := 0
    for &node in definition.nodes {
        if node.kind != .Objective do continue
        node_status := quest.status(&editor.story_state.quest, definition, node.id)
        completed := quest.completion_count(&editor.story_state.quest, definition, node.id) > 0
        include := tab == .Active ? quest.is_presented(&editor.story_state.quest, definition, node.id) : completed
        if !include || count >= QUEST_LOG_MAX_ITEMS do continue
        items[count] = node.id
        count += 1
    }

    // Active work follows activation order; finished work reads newest first.
    for index in 1 ..< count {
        value := items[index]
        cursor := index
        for cursor > 0 {
            left := items[cursor - 1]
            left_order := quest.activation_sequence(&editor.story_state.quest, definition, left)
            value_order := quest.activation_sequence(&editor.story_state.quest, definition, value)
            if tab == .Completed {
                left_order = quest.completion_sequence(&editor.story_state.quest, definition, left)
                value_order = quest.completion_sequence(&editor.story_state.quest, definition, value)
            }
            ordered := tab == .Active ? left_order <= value_order : left_order >= value_order
            if ordered do break
            items[cursor] = left
            cursor -= 1
        }
        items[cursor] = value
    }
    return count
}

quest_log_first_active :: proc(editor: ^Editor) -> quest.Node_ID {
    if editor == nil do return quest.no_node
    return quest.first_active(&editor.story_state.quest, &editor.story_quest_catalog.definition)
}

quest_tracking_refresh :: proc(editor: ^Editor) {
    if editor == nil do return
    _ = story.ensure_quest_progress(&editor.story_state)
    definition := &editor.story_quest_catalog.definition
    revision_changed := editor.quest_tracking_revision != editor.story_state.quest.revision
    if quest.is_active(&editor.story_state.quest, definition, editor.tracked_quest_node) {
        editor.quest_tracking_revision = editor.story_state.quest.revision
        return
    }

    preferred := quest.preferred_tracking(&editor.story_state.quest, definition, editor.tracked_quest_node)
    if editor.tracked_quest_node != quest.no_node && preferred != quest.no_node {
        editor.tracked_quest_node = preferred
        editor.quest_tracking_suppressed = false
        editor.quest_tracking_revision = editor.story_state.quest.revision
        return
    }

    editor.tracked_quest_node = quest.no_node
    if editor.quest_tracking_suppressed && !revision_changed do return
    editor.quest_tracking_suppressed = false
    editor.tracked_quest_node = preferred
    editor.quest_tracking_revision = editor.story_state.quest.revision
}

quest_log_toggle_tracking :: proc(editor: ^Editor, id: quest.Node_ID) {
    if editor == nil do return
    definition := &editor.story_quest_catalog.definition
    node_status := quest.status(&editor.story_state.quest, definition, id)
    if node_status != .Active && node_status != .Available do return
    if editor.tracked_quest_node == id {
        editor.tracked_quest_node = quest.no_node
        editor.quest_tracking_suppressed = true
    } else {
        editor.tracked_quest_node = id
        editor.quest_tracking_suppressed = false
    }
    editor.quest_tracking_revision = editor.story_state.quest.revision
}

quest_log_open :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map || editor.attendant_dialogue_open do return
    quest_tracking_refresh(editor)
    menu_scene_push(editor, .Journal)
    editor.quest_log_tab = .Active
    editor.quest_log_focus = 0
    editor.quest_log_scroll = 0
    editor.map_time = f32(canvas2d.GetTime())
    game_input.reset_menu_repeat(&editor.runtime_input)
    set_pointer_locked(false)
}

quest_log_close :: proc(editor: ^Editor) {
    if editor == nil do return
    pause_menu_resume(editor)
}

quest_log_clamp_focus :: proc(editor: ^Editor, count, visible_rows: int) {
    if editor == nil do return
    if count <= 0 {
        editor.quest_log_focus = 0
        editor.quest_log_scroll = 0
        return
    }
    editor.quest_log_focus = clamp(editor.quest_log_focus, 0, count - 1)
    max_scroll := max(count - visible_rows, 0)
    if editor.quest_log_focus < editor.quest_log_scroll {
        editor.quest_log_scroll = editor.quest_log_focus
    } else if editor.quest_log_focus >= editor.quest_log_scroll + visible_rows {
        editor.quest_log_scroll = editor.quest_log_focus - visible_rows + 1
    }
    editor.quest_log_scroll = clamp(editor.quest_log_scroll, 0, max_scroll)
}

quest_log_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil do return
    layout := quest_log_layout(width, height)
    items: [QUEST_LOG_MAX_ITEMS]quest.Node_ID
    count := quest_log_collect(editor, editor.quest_log_tab, &items)
    visible_rows := max(int(layout.list.height / QUEST_LOG_ROW_HEIGHT), 1)
    quest_log_clamp_focus(editor, count, visible_rows)

    horizontal, vertical := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    if canvas2d.IsKeyPressed(.LEFT) || gamepad_pressed(.Dpad_Left) do horizontal = -1
    if canvas2d.IsKeyPressed(.RIGHT) || gamepad_pressed(.Dpad_Right) do horizontal = 1
    if horizontal != 0 {
        editor.quest_log_tab = horizontal < 0 ? .Active : .Completed
        editor.quest_log_focus = 0
        editor.quest_log_scroll = 0
        count = quest_log_collect(editor, editor.quest_log_tab, &items)
        quest_log_clamp_focus(editor, count, visible_rows)
    }
    if canvas2d.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) do vertical = -1
    if canvas2d.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) do vertical = 1
    if vertical != 0 {
        editor.quest_log_focus += vertical
        quest_log_clamp_focus(editor, count, visible_rows)
    }

    mouse := canvas2d.GetMousePosition()
    mouse_delta := canvas2d.GetMouseDelta()
    mouse_active :=
        canvas2d.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        for tab in Quest_Log_Tab {
            if canvas2d.CheckCollisionPointRec(mouse, quest_log_tab_bounds(layout, tab)) {
                editor.quest_log_tab = tab
                editor.quest_log_focus = 0
                editor.quest_log_scroll = 0
                count = quest_log_collect(editor, editor.quest_log_tab, &items)
            }
        }
    }
    if count > 0 && canvas2d.CheckCollisionPointRec(mouse, layout.list) {
        wheel := canvas2d.GetMouseWheelMove()
        if wheel != 0 {
            editor.quest_log_scroll = clamp(editor.quest_log_scroll - int(wheel), 0, max(count - visible_rows, 0))
            editor.quest_log_focus = clamp(
                editor.quest_log_focus,
                editor.quest_log_scroll,
                min(editor.quest_log_scroll + visible_rows - 1, count - 1),
            )
        }
        if mouse_active {
            for row in 0 ..< min(visible_rows, count - editor.quest_log_scroll) {
                if canvas2d.CheckCollisionPointRec(mouse, quest_log_row_bounds(layout, row)) {
                    editor.quest_log_focus = editor.quest_log_scroll + row
                }
            }
        }
    }

    selected := count > 0 ? items[editor.quest_log_focus] : quest.no_node
    if input_action_pressed(.Menu_Accept) && editor.quest_log_tab == .Active && selected != quest.no_node {
        quest_log_toggle_tracking(editor, selected)
    }
    if canvas2d.IsMouseButtonPressed(.LEFT) &&
       editor.quest_log_tab == .Active &&
       selected != quest.no_node &&
       canvas2d.CheckCollisionPointRec(mouse, layout.track_button) {
        quest_log_toggle_tracking(editor, selected)
    }
}

quest_log_draw_tab :: proc(layout: Quest_Log_Layout, tab: Quest_Log_Tab, selected: bool) {
    bounds := quest_log_tab_bounds(layout, tab)
    style := ui_theme_control_style(selected ? .Selected : .Resting)
    canvas2d.DrawRectangleRounded(bounds, .16, 8, style.fill)
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .16, 8, style.border_width, style.border)
    label: cstring = tab == .Active ? "ACTIVE" : "COMPLETED"
    size := ui_measure_text(.Label, label, .35)
    ui_draw_text(.Label, label, {bounds.x + (bounds.width - size.x) * .5, bounds.y + 13}, .35, style.text)
}

quest_log_draw :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil do return
    layout := quest_log_layout(width, height)
    canvas2d.DrawRectangle(0, 0, width, height, ui_theme_scrim(210))
    canvas2d.DrawRectangleRounded(layout.panel, .025, 12, ui_theme_surface())
    canvas2d.DrawRectangleRoundedLinesEx(layout.panel, .025, 12, 2, ui_theme_border_strong())

    ui_draw_text(.Data, "COURIER'S", {layout.panel.x + 28, layout.panel.y + 20}, .45, ui_theme_accent())
    ui_draw_text(.Display, "LEDGER", {layout.panel.x + 28, layout.panel.y + 44}, .55, ui_theme_text())
    ui_draw_text(
        .Data,
        fmt.ctprintf("%s", editor.story_quest_catalog.definition.title),
        {layout.panel.x + 180, layout.panel.y + 58},
        .3,
        ui_theme_text_muted(),
    )
    stamps := fmt.ctprintf("%d STAMPS", editor.story_state.stamps_earned)
    if story.has_friendometer(&editor.story_state) {
        stamps = fmt.ctprintf(
            "%d FRIENDSHIP · %d STAMPS",
            editor.story_state.friendship_points,
            editor.story_state.stamps_earned,
        )
    }
    if editor.story_state.bonus_stamps > 0 {
        if story.has_friendometer(&editor.story_state) {
            stamps = fmt.ctprintf(
                "%d FRIENDSHIP · %d STAMPS · %d MERIT",
                editor.story_state.friendship_points,
                editor.story_state.stamps_earned,
                editor.story_state.bonus_stamps,
            )
        } else {
            stamps = fmt.ctprintf(
                "%d STAMPS · %d MERIT",
                editor.story_state.stamps_earned,
                editor.story_state.bonus_stamps,
            )
        }
    }
    stamp_size := ui_measure_text(.Data, stamps, .35)
    ui_draw_text(
        .Data,
        stamps,
        {layout.panel.x + layout.panel.width - stamp_size.x - 28, layout.panel.y + 54},
        .35,
        ui_theme_accent(),
    )
    canvas2d.DrawLineEx(
        {layout.panel.x + 24, layout.panel.y + layout.header.height - 10},
        {layout.panel.x + layout.panel.width - 24, layout.panel.y + layout.header.height - 10},
        1,
        ui_theme_border(),
    )

    quest_log_draw_tab(layout, .Active, editor.quest_log_tab == .Active)
    quest_log_draw_tab(layout, .Completed, editor.quest_log_tab == .Completed)

    items: [QUEST_LOG_MAX_ITEMS]quest.Node_ID
    count := quest_log_collect(editor, editor.quest_log_tab, &items)
    visible_rows := max(int(layout.list.height / QUEST_LOG_ROW_HEIGHT), 1)
    quest_log_clamp_focus(editor, count, visible_rows)
    if count == 0 {
        empty: cstring = editor.quest_log_tab == .Active ? "No errands waiting" : "No deliveries recorded yet"
        ui_draw_text(.Body, empty, {layout.list.x + 18, layout.list.y + 28}, .2, ui_theme_text_muted())
    } else {
        canvas2d.BeginScissorMode(layout.list)
        for row in 0 ..< min(visible_rows, count - editor.quest_log_scroll) {
            index := editor.quest_log_scroll + row
            id := items[index]
            node := quest.find_node(&editor.story_quest_catalog.definition, id)
            if node == nil do continue
            bounds := quest_log_row_bounds(layout, row)
            focused := index == editor.quest_log_focus
            tracked := id == editor.tracked_quest_node
            state := focused ? UI_Control_State.Focused : (tracked ? UI_Control_State.Selected : .Resting)
            style := ui_theme_control_style(state)
            canvas2d.DrawRectangleRounded(bounds, .1, 8, style.fill)
            canvas2d.DrawRectangleRoundedLinesEx(bounds, .1, 8, style.border_width, style.border)
            title := fmt.ctprintf("%s", node.title)
            ui_draw_text(.Label, title, {bounds.x + 14, bounds.y + 10}, .25, style.text)
            meta := fmt.ctprintf("%s", node.location)
            if editor.quest_log_tab == .Completed && node.repeatable {
                meta = fmt.ctprintf(
                    "%s  ·  %d COMPLETED",
                    node.location,
                    quest.completion_count(&editor.story_state.quest, &editor.story_quest_catalog.definition, id),
                )
            }
            ui_draw_text(
                .Data,
                meta,
                {bounds.x + 14, bounds.y + 32},
                .15,
                focused ? ui_theme_text_muted() : style.text,
            )
        }
        canvas2d.EndScissorMode()
    }

    canvas2d.DrawRectangleRounded(layout.detail, .025, 10, ui_theme_surface_elevated())
    canvas2d.DrawRectangleRoundedLinesEx(layout.detail, .025, 10, 1, ui_theme_border())
    if count > 0 {
        id := items[editor.quest_log_focus]
        node := quest.find_node(&editor.story_quest_catalog.definition, id)
        if node != nil {
            status_label: cstring =
                editor.quest_log_tab == .Completed ? "COMPLETED" : (id == editor.tracked_quest_node ? "TRACKED" : "ACTIVE")
            ui_draw_text(.Data, status_label, {layout.detail.x + 24, layout.detail.y + 24}, .35, ui_theme_accent())
            dialogue_draw_wrapped(
                node.title,
                {layout.detail.x + 24, layout.detail.y + 48, layout.detail.width - 48, 76},
                layout.detail.height < 430 ? f32(26) : f32(30),
                1,
                layout.detail.height < 430 ? f32(32) : f32(36),
                ui_theme_text(),
            )
            ui_draw_text(.Data, "LOCATION", {layout.detail.x + 24, layout.detail.y + 130}, .25, ui_theme_text_muted())
            ui_draw_text(
                .Label,
                fmt.ctprintf("%s", node.location),
                {layout.detail.x + 24, layout.detail.y + 152},
                .25,
                ui_theme_text(),
            )
            instruction_y := layout.detail.y + 190
            dialogue_draw_wrapped(
                node.instruction,
                {
                    layout.detail.x + 24,
                    instruction_y,
                    layout.detail.width - 48,
                    max(layout.track_button.y - instruction_y - 12, f32(28)),
                },
                layout.detail.height < 430 ? f32(20) : f32(24),
                .7,
                layout.detail.height < 430 ? f32(26) : f32(31),
                ui_theme_text(),
            )
            if editor.quest_log_tab == .Active {
                tracked := id == editor.tracked_quest_node
                pause_menu_button(layout.track_button, tracked ? "UNTRACK" : "TRACK THIS ERRAND", !tracked, false)
            }
        }
    }

    hint: cstring = "J closes  |  ARROWS select  |  ENTER tracks"
    if controller_prompt_active(editor) {
        hint = fmt.ctprintf(
            "LB / RB map  |  %s closes  |  D-PAD / LS selects  |  %s tracks",
            controller_journal_label(editor),
            controller_face_label(editor, .South),
        )
    }
    hint_size := ui_measure_text(.Data, hint, .2)
    ui_draw_text(
        .Data,
        hint,
        {layout.panel.x + layout.panel.width - hint_size.x - 28, layout.panel.y + layout.panel.height - 18},
        .2,
        ui_theme_text_muted(),
    )
}

quest_tracking_hud_draw :: proc(editor: ^Editor, width: i32) {
    if editor == nil ||
       !editor.in_map ||
       !editor.gameplay_options.show_hud ||
       editor.attendant_dialogue_open ||
       pause_menu_is_open(editor) {
        return
    }
    quest_tracking_refresh(editor)
    node := quest.find_node(&editor.story_quest_catalog.definition, editor.tracked_quest_node)
    if node == nil do return
    panel_width := min(f32(390), f32(width) - 28)
    panel := canvas2d.Rectangle{14, 82, panel_width, 76}
    canvas2d.DrawRectangleRounded(panel, .12, 8, ui_theme_surface(236))
    canvas2d.DrawRectangleRoundedLinesEx(panel, .12, 8, 1, ui_theme_border())
    ui_draw_text(.Data, "TRACKED ERRAND", {panel.x + 14, panel.y + 10}, .22, ui_theme_accent())
    ui_draw_text(.Label, fmt.ctprintf("%s", node.title), {panel.x + 14, panel.y + 32}, .22, ui_theme_text())
    ui_draw_text(.Data, fmt.ctprintf("%s", node.location), {panel.x + 14, panel.y + 54}, .16, ui_theme_text_muted())
}

FRIENDSHIP_NOTICE_DURATION :: f32(2.35)
FRIENDSHIP_NOTICE_ENTER :: f32(.24)
FRIENDSHIP_NOTICE_EXIT :: f32(.42)

friendship_notice_step :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    total := editor.story_state.friendship_points
    if !editor.friendship_notice_initialized {
        editor.friendship_notice_initialized = true
        editor.friendship_notice_total = total
        editor.friendship_notice_age = FRIENDSHIP_NOTICE_DURATION
        return
    }
    if total != editor.friendship_notice_total {
        editor.friendship_notice_delta = total - editor.friendship_notice_total
        editor.friendship_notice_total = total
        editor.friendship_notice_age = 0
    } else {
        editor.friendship_notice_age = min(
            editor.friendship_notice_age + max(delta_seconds, f32(0)),
            FRIENDSHIP_NOTICE_DURATION,
        )
    }
}

friendship_notice_ease :: proc(value: f32) -> f32 {
    t := clamp(value, f32(0), f32(1))
    return 1 - (1 - t) * (1 - t) * (1 - t)
}

friendship_notice_draw :: proc(editor: ^Editor, width: i32) {
    if editor == nil ||
       !editor.in_map ||
       !editor.gameplay_options.show_hud ||
       pause_menu_is_open(editor) ||
       !story.has_friendometer(&editor.story_state) ||
       editor.friendship_notice_delta == 0 ||
       editor.friendship_notice_age >= FRIENDSHIP_NOTICE_DURATION {
        return
    }

    age := editor.friendship_notice_age
    visibility := f32(1)
    if age < FRIENDSHIP_NOTICE_ENTER {
        visibility = friendship_notice_ease(age / FRIENDSHIP_NOTICE_ENTER)
    } else if age > FRIENDSHIP_NOTICE_DURATION - FRIENDSHIP_NOTICE_EXIT {
        visibility = clamp((FRIENDSHIP_NOTICE_DURATION - age) / FRIENDSHIP_NOTICE_EXIT, f32(0), f32(1))
    }
    alpha := u8(clamp(visibility * 255, f32(0), f32(255)))
    panel_width := min(f32(310), f32(width) - 28)
    panel_height := f32(68)
    resting_y := f32(24)
    y := resting_y - (1 - visibility) * 22
    panel := canvas2d.Rectangle{(f32(width) - panel_width) * .5, y, panel_width, panel_height}

    canvas2d.DrawRectangleRounded(panel, .22, 10, ui_theme_surface(u8(f32(alpha) * .94)))
    canvas2d.DrawRectangleRoundedLinesEx(panel, .22, 10, 2, ui_theme_accent(alpha))

    reward := fmt.ctprintf("+%d FRIENDSHIP", editor.friendship_notice_delta)
    reward_size := ui_measure_text(.Label, reward, .3)
    ui_draw_text(
        .Label,
        reward,
        {panel.x + (panel.width - reward_size.x) * .5, panel.y + 13},
        .3,
        ui_theme_accent(alpha),
    )
    total := fmt.ctprintf("%d TOTAL", editor.friendship_notice_total)
    total_size := ui_measure_text(.Data, total, .18)
    ui_draw_text(
        .Data,
        total,
        {panel.x + (panel.width - total_size.x) * .5, panel.y + 43},
        .18,
        ui_theme_text_muted(alpha),
    )
}
