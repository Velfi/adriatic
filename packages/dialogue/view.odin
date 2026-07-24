package dialogue

// Optional presentation adapter for Zelda Engine's immediate-mode UI. The
// conversation runtime remains usable without this file's UI dependency; the
// owning application supplies the engine Gui_Context and decides when the view
// is open.

import ui "zelda_engine:ui"

View_Result :: enum {
    None,
    Chosen,
    Closed,
}

// draw_view renders one conversation panel and returns the interaction that
// occurred this frame. Choice indices are the filtered/visible indices used by
// choose, so hidden conditional choices never create dead buttons.
draw_view :: proc(ctx: ^ui.Gui_Context, conversation: ^Conversation, bounds: ui.Rect, key: string) -> View_Result {
    if ctx == nil || conversation == nil || conversation.ended do return .None
    current_node := current(conversation)
    if current_node == nil do return .None

    panel_id := ui.gui_make_id(ctx, key)
    ui.gui_panel_begin(ctx, bounds)
    defer ui.gui_panel_end(ctx)

    leave_bounds := ui.gui_next_rect(
        ctx,
        width = ctx.style.row_height * 2,
        height = ctx.style.row_height,
        stretch_cross_axis = false,
    )
    if ui.gui_button_at(ctx, ui.gui_id_child(panel_id, "leave"), leave_bounds, "Leave", true) do return .Closed
    ui.gui_heading(ctx, current_node.speaker(&conversation.ctx))
    ui.gui_text_block(
        ctx,
        current_node.text(&conversation.ctx),
        bounds.w - ctx.style.panel_padding * 2,
        ctx.style.text,
    )
    ui.gui_rhythm_spacer(ctx, .Half)

    for visible_index in 0 ..< available_count(conversation) {
        response := available_at(conversation, visible_index)
        if response == nil do continue
        button_id := ui.gui_id_child_int(panel_id, visible_index)
        button_bounds := ui.gui_next_rect(ctx, height = ctx.style.row_height)
        if ui.gui_button_at(ctx, button_id, button_bounds, response.text, true) {
            if choose(conversation, visible_index) do return .Chosen
        }
    }
    return .None
}
