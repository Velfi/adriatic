package main

import third_person "../packages/third_person"
import canvas2d "zelda_engine:canvas2d"

World_Label_Placement :: enum {
    Above,
    Below,
    Left,
    Right,
}

World_Label_Style :: struct {
    placement:        World_Label_Placement,
    gap:              f32,
    width:            f32,
    height:           f32,
    viewport_padding: f32,
    font_size:        f32,
    text_spacing:     f32,
    background:       canvas2d.Color,
    text:             canvas2d.Color,
    leader:           canvas2d.Color,
}

world_label_style :: proc(placement := World_Label_Placement.Below) -> World_Label_Style {
    return {
        placement = placement,
        gap = 12,
        width = 108,
        height = 25,
        viewport_padding = 8,
        font_size = 11,
        text_spacing = 1,
        background = {19, 31, 27, 210},
        text = {232, 224, 189, 255},
        leader = {174, 207, 160, 190},
    }
}

world_label_bounds :: proc(
    anchor: canvas2d.Vector2,
    viewport_width, viewport_height: f32,
    style: World_Label_Style,
) -> (
    canvas2d.Rectangle,
    bool,
) {
    x := anchor.x - style.width * .5
    y := anchor.y + style.gap
    #partial switch style.placement {
    case .Above:
        y = anchor.y - style.gap - style.height
    case .Below:
    case .Left:
        x = anchor.x - style.gap - style.width
        y = anchor.y - style.height * .5
    case .Right:
        x = anchor.x + style.gap
        y = anchor.y - style.height * .5
    }
    unclamped_x, unclamped_y := x, y
    limit_x := max(style.viewport_padding, viewport_width - style.width - style.viewport_padding)
    limit_y := max(style.viewport_padding, viewport_height - style.height - style.viewport_padding)
    x = clamp(x, style.viewport_padding, limit_x)
    y = clamp(y, style.viewport_padding, limit_y)
    displaced := abs(x - unclamped_x) > .5 || abs(y - unclamped_y) > .5
    return {x, y, style.width, style.height}, displaced
}

// Draw a UI label attached to a point in the 3D scene. The caller chooses the
// semantic side of the point; projection, behind-camera rejection, viewport
// fitting, and a leader for displaced panels are handled here.
world_label_draw :: proc(
    editor: ^Editor,
    point: third_person.Vec3,
    width, height: i32,
    text: cstring,
    style: World_Label_Style = {},
) -> bool {
    if editor == nil || width <= 0 || height <= 0 do return false
    resolved_style := style
    if resolved_style.width <= 0 || resolved_style.height <= 0 {
        resolved_style = world_label_style()
    }
    projected := project_3d(perspective_camera(editor.camera_pose), point, width, height)
    if !projected.visible do return false

    // Reject distant off-screen anchors. A small allowance lets a clamped
    // label identify something just beyond an edge without creating UI for a
    // point that is nowhere near the current view.
    allowance := max(resolved_style.width, resolved_style.height)
    if projected.position.x < -allowance ||
       projected.position.x > f32(width) + allowance ||
       projected.position.y < -allowance ||
       projected.position.y > f32(height) + allowance {
        return false
    }

    return screen_label_draw(projected.position, width, height, text, resolved_style)
}

// Screen-space companion for callers that project a whole 3D silhouette and
// want to attach a label to its edge rather than to an arbitrary center point.
screen_label_draw :: proc(
    anchor: canvas2d.Vector2,
    width, height: i32,
    text: cstring,
    style: World_Label_Style = {},
) -> bool {
    if width <= 0 || height <= 0 do return false
    resolved_style := style
    if resolved_style.width <= 0 || resolved_style.height <= 0 {
        resolved_style = world_label_style()
    }
    allowance := max(resolved_style.width, resolved_style.height)
    if anchor.x < -allowance ||
       anchor.x > f32(width) + allowance ||
       anchor.y < -allowance ||
       anchor.y > f32(height) + allowance {
        return false
    }

    bounds, displaced := world_label_bounds(anchor, f32(width), f32(height), resolved_style)
    if displaced {
        attachment := canvas2d.Vector2 {
            clamp(anchor.x, bounds.x, bounds.x + bounds.width),
            clamp(anchor.y, bounds.y, bounds.y + bounds.height),
        }
        canvas2d.DrawLineEx(anchor, attachment, 1, resolved_style.leader)
    }
    canvas2d.DrawRectangleRounded(bounds, .3, 6, resolved_style.background)
    measured := canvas2d.MeasureTextEx(canvas2d.Font{}, text, resolved_style.font_size, resolved_style.text_spacing)
    text_position := canvas2d.Vector2 {
        bounds.x + max((bounds.width - measured.x) * .5, f32(6)),
        // MeasureTextEx includes the font's full line box, whose unused
        // ascender/descender space makes all-cap labels look too high. Center
        // the requested em size instead; this matches DrawTextEx's visual ink.
        bounds.y + (bounds.height - resolved_style.font_size) * .5,
    }
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        text,
        text_position,
        resolved_style.font_size,
        resolved_style.text_spacing,
        resolved_style.text,
    )
    return true
}
