package main
import "core:math"
import "core:testing"

import cinematic "../packages/cinematic"
import particles "../packages/particles"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math/linalg"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"

cinematic_render_camera :: proc(ctx: ^Render_Graph_Context, value: cinematic.Camera) {
    pose := third_person.Camera_Pose {
        position = {value.position[0], value.position[1], value.position[2]},
        target   = {value.target[0], value.target[1], value.target[2]},
    }
    camera := perspective_camera(pose, max(value.focal_length, f32(.01)))
    aspect := f32(ctx.pass.framebuffer_extent.width) / f32(max(ctx.pass.framebuffer_extent.height, 1))
    ctx.world_push.camera_position = {
        camera.position.x,
        camera.position.y,
        camera.position.z,
        ctx.world_push.camera_position[3],
    }
    ctx.world_push.camera_right = {camera.right.x, camera.right.y, camera.right.z, ctx.world_push.camera_right[3]}
    ctx.world_push.camera_up = {camera.up.x, camera.up.y, camera.up.z, ctx.world_push.camera_up[3]}
    ctx.world_push.camera_forward = {
        camera.forward.x,
        camera.forward.y,
        camera.forward.z,
        ctx.world_push.camera_forward[3],
    }
    ctx.world_push.projection[0] = camera.focal_length
    ctx.world_push.projection[1] = aspect
    ctx.sky_push.camera_right = {camera.right.x, camera.right.y, camera.right.z, aspect}
    ctx.sky_push.camera_up = {camera.up.x, camera.up.y, camera.up.z, camera.focal_length}
    ctx.sky_push.camera_forward = {camera.forward.x, camera.forward.y, camera.forward.z, 0}
}

cinematic_wipe_append_rect :: proc(rects: ^[128]vk.Rect2D, count: ^int, rect: vk.Rect2D) {
    if rects == nil || count == nil || count^ >= len(rects) || rect.extent.width == 0 || rect.extent.height == 0 do return
    rects[count^] = rect
    count^ += 1
}

cinematic_wipe_rects :: proc(
    extent: vk.Extent2D,
    kind: cinematic.Wipe_Kind,
    progress: f32,
    rects: ^[128]vk.Rect2D,
) -> int {
    if rects == nil || kind == .None do return 0
    p := clamp(progress, 0, 1)
    width, height := extent.width, extent.height
    if p <= 0 do return 0
    if p >= .9999 {
        rects[0] = {
            extent = extent,
        }
        return 1
    }
    count := 0
    #partial switch kind {
    case .Left:
        cinematic_wipe_append_rect(rects, &count, {extent = {max(u32(f32(width) * p), 1), height}})
    case .Right:
        amount := max(u32(f32(width) * p), 1)
        cinematic_wipe_append_rect(rects, &count, {offset = {i32(width - amount), 0}, extent = {amount, height}})
    case .Up:
        amount := max(u32(f32(height) * p), 1)
        cinematic_wipe_append_rect(rects, &count, {offset = {0, i32(height - amount)}, extent = {width, amount}})
    case .Down:
        cinematic_wipe_append_rect(rects, &count, {extent = {width, max(u32(f32(height) * p), 1)}})
    case .Iris:
        band_count := 36
        band_height := f32(height) / f32(band_count)
        radius := f32(math.sqrt(f64(width * width + height * height))) * .5 * p
        center_x, center_y := f32(width) * .5, f32(height) * .5
        for band in 0 ..< band_count {
            y0 := f32(band) * band_height
            y1 := min(f32(band + 1) * band_height, f32(height))
            dy := (y0 + y1) * .5 - center_y
            if abs(dy) > radius do continue
            half_width := f32(math.sqrt(f64(max(radius * radius - dy * dy, 0))))
            x0 := u32(clamp(center_x - half_width, 0, f32(width)))
            x1 := u32(clamp(center_x + half_width, 0, f32(width)))
            cinematic_wipe_append_rect(
                rects,
                &count,
                {offset = {i32(x0), i32(y0)}, extent = {max(x1 - x0, u32(1)), max(u32(y1) - u32(y0), u32(1))}},
            )
        }
    case .Clockwise:
        columns, rows := 32, 18
        cell_width, cell_height := f32(width) / f32(columns), f32(height) / f32(rows)
        limit := p * 2 * f32(math.PI)
        for row in 0 ..< rows {
            run_start := -1
            for column in 0 ..= columns {
                inside := false
                if column < columns {
                    x := (f32(column) + .5) * cell_width - f32(width) * .5
                    y := (f32(row) + .5) * cell_height - f32(height) * .5
                    angle := f32(math.atan2(f64(x), f64(-y)))
                    if angle < 0 do angle += 2 * f32(math.PI)
                    inside = angle <= limit
                }
                if inside && run_start < 0 do run_start = column
                if !inside && run_start >= 0 {
                    x0 := u32(f32(run_start) * cell_width)
                    x1 := u32(min(f32(column) * cell_width, f32(width)))
                    y0 := u32(f32(row) * cell_height)
                    y1 := u32(min(f32(row + 1) * cell_height, f32(height)))
                    cinematic_wipe_append_rect(
                        rects,
                        &count,
                        {offset = {i32(x0), i32(y0)}, extent = {x1 - x0, y1 - y0}},
                    )
                    run_start = -1
                }
            }
        }
    case .Checker:
        columns, rows := 12, 8
        cell_width, cell_height := f32(width) / f32(columns), f32(height) / f32(rows)
        threshold := p * 2
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                phase := f32((row + column) & 1)
                cell_progress := clamp(threshold - phase, 0, 1)
                if cell_progress <= 0 do continue
                x0 := u32(f32(column) * cell_width)
                x1 := u32(min((f32(column) + cell_progress) * cell_width, f32(width)))
                y0 := u32(f32(row) * cell_height)
                y1 := u32(min(f32(row + 1) * cell_height, f32(height)))
                cinematic_wipe_append_rect(
                    rects,
                    &count,
                    {offset = {i32(x0), i32(y0)}, extent = {max(x1 - x0, u32(1)), max(y1 - y0, u32(1))}},
                )
            }
        }
    }
    return count
}

cinematic_render_world_without_sky :: proc(ctx: ^Render_Graph_Context) {
    // Keep this order aligned with adriatic_render_graph's dependencies.
    render_graph_terrain(ctx)
    render_graph_geometry(ctx)
    render_graph_foliage(ctx)
    render_graph_roads(ctx)
    render_graph_transparent(ctx)
}

// Initial host-buffer and CPU-array reserves. Frame-slot buffers grow when a
// larger authored world needs them.
