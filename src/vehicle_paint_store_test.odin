package main

import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import rl "zelda_engine:canvas2d"

when ODIN_TEST {
    vehicle_paint_test_uv :: proc(x, y: int) -> [2]f32 {
        return {
            (f32(x) + .5) / VEHICLE_PAINT_TEXTURE_WIDTH,
            (f32(y) + .5) / VEHICLE_PAINT_TEXTURE_HEIGHT,
        }
    }

    @(test)
    vehicle_paint_store_round_trips_and_rejects_corruption :: proc(t: ^testing.T) {
        directory, directory_err := os.make_directory_temp("", "adriatic-paint-*", context.allocator)
        testing.expect(t, directory_err == nil)
        if directory_err != nil do return
        path, path_err := strings.concatenate({directory, "/paint.bin"}, context.allocator)
        testing.expect(t, path_err == nil)
        if path_err != nil do return
        defer {
            _ = os.remove(path)
            _ = os.remove(directory)
            delete(path)
            delete(directory)
        }

        source := new(Editor)
        restored := new(Editor)
        defer free(source)
        defer free(restored)
        source.vehicle_paint_layers[0][17] = 42
        source.vehicle_paint_layers[1][1024] = 197
        source.vehicle_paint_layers[2][VEHICLE_PAINT_TEXTURE_BYTE_COUNT - 1] = 255

        testing.expect(t, vehicle_paint_save_to_path(source, path))
        testing.expect(t, vehicle_paint_load_from_path(restored, path))
        testing.expect(
            t,
            vehicle_paint_checksum(vehicle_paint_layer_bytes(source)) ==
                vehicle_paint_checksum(vehicle_paint_layer_bytes(restored)),
        )

        bytes, read_err := os.read_entire_file(path, context.allocator)
        testing.expect(t, read_err == nil)
        if read_err != nil do return
        defer delete(bytes)
        bytes[len(bytes) - 1] ~= 0xff
        testing.expect(t, os.write_entire_file(path, bytes) == nil)
        restored.vehicle_paint_layers[0][17] = 99
        testing.expect(t, !vehicle_paint_load_from_path(restored, path))
        testing.expect(t, restored.vehicle_paint_layers[0][17] == 99)
    }

    @(test)
    vehicle_paint_tools_respect_ownership_and_history :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        vehicle_paint_history_init(editor)
        defer vehicle_paint_history_destroy(editor)
        editor.vehicle_paint_component_mask = {true, true, true, true, true}
        editor.vehicle_paint_brush_radius = 4
        part := vehicles.Aircraft_Mesh_Part.Body
        owner := u8(part) + 1
        pixels := vehicle_paint_pixels(editor)

        // Two UV islands owned by the same mesh part must remain disconnected.
        for y in 10 ..= 19 {
            for x in 10 ..= 19 {
                editor.vehicle_paint_texel_part[y * VEHICLE_PAINT_TEXTURE_WIDTH + x] = owner
            }
            for x in 22 ..= 29 {
                editor.vehicle_paint_texel_part[y * VEHICLE_PAINT_TEXTURE_WIDTH + x] = owner
            }
        }
        red := rl.Color{220, 20, 30, 255}
        blue := rl.Color{20, 60, 220, 255}
        vehicle_paint_history_capture(editor)
        vehicle_paint_bucket(editor, part, vehicle_paint_test_uv(14, 14), red)
        testing.expect(t, vehicle_paint_history_commit(editor))
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 14) * 4] == red.r)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 24) * 4 + 3] == 0)

        vehicle_paint_history_capture(editor)
        vehicle_paint_pattern(editor, part, vehicle_paint_test_uv(24, 14), red, blue)
        testing.expect(t, vehicle_paint_history_commit(editor))
        first_pattern := pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 24) * 4]
        second_pattern := pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 28) * 4]
        testing.expect(t, first_pattern != second_pattern)

        vehicle_paint_history_undo(editor)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 24) * 4 + 3] == 0)
        vehicle_paint_history_undo(editor)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 14) * 4 + 3] == 0)
        vehicle_paint_history_redo(editor)
        vehicle_paint_history_redo(editor)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 14) * 4] == red.r)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 24) * 4 + 3] == 255)

        // Gradient produces both endpoint colors but cannot leave the island.
        vehicle_paint_gradient(
            editor,
            part,
            vehicle_paint_test_uv(10, 14),
            vehicle_paint_test_uv(19, 14),
            red,
            blue,
        )
        left := (14 * VEHICLE_PAINT_TEXTURE_WIDTH + 10) * 4
        right := (14 * VEHICLE_PAINT_TEXTURE_WIDTH + 19) * 4
        testing.expect(t, pixels[left] > pixels[right])
        testing.expect(t, pixels[left + 2] < pixels[right + 2])

        // Shape and strip are hard edged and ownership clipped.
        vehicle_paint_shape(editor, part, vehicle_paint_test_uv(14, 14), blue)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 14) * 4 + 2] == blue.b)
        disconnected_near_strip := 12 * VEHICLE_PAINT_TEXTURE_WIDTH + 22
        vehicle_paint_set_texel(pixels, disconnected_near_strip, {}, 0)
        vehicle_paint_strip(
            editor,
            part,
            vehicle_paint_test_uv(10, 12),
            vehicle_paint_test_uv(19, 12),
            red,
        )
        testing.expect(t, pixels[(12 * VEHICLE_PAINT_TEXTURE_WIDTH + 15) * 4] == red.r)
        testing.expect(t, pixels[disconnected_near_strip * 4 + 3] == 0)
        testing.expect(t, pixels[(12 * VEHICLE_PAINT_TEXTURE_WIDTH + 24) * 4] != red.r)

        // Blend changes a discontinuity but never samples the neighboring island.
        center := 15 * VEHICLE_PAINT_TEXTURE_WIDTH + 15
        neighbor := 15 * VEHICLE_PAINT_TEXTURE_WIDTH + 16
        vehicle_paint_set_texel(pixels, center, red)
        vehicle_paint_set_texel(pixels, neighbor, blue)
        before_red := pixels[center * 4]
        vehicle_paint_blend(editor, part, vehicle_paint_test_uv(15, 15))
        testing.expect(t, pixels[center * 4] < before_red)
        testing.expect(t, pixels[(15 * VEHICLE_PAINT_TEXTURE_WIDTH + 24) * 4 + 3] == 255)
    }

    @(test)
    vehicle_paint_symmetry_resolves_the_opposite_surface_not_flipped_uv :: proc(t: ^testing.T) {
        mesh: vehicles.Aircraft_Mesh
        mesh.vertex_count = 6
        mesh.triangle_count = 2
        mesh.vertices[0] = {position = {-1, 0, 0}, uv = {.10, .10}, part = .Wing}
        mesh.vertices[1] = {position = {-1, 1, 0}, uv = {.10, .20}, part = .Wing}
        mesh.vertices[2] = {position = {-1, 0, 1}, uv = {.20, .10}, part = .Wing}
        // The opposite triangle deliberately lives in an unrelated area of
        // the packed atlas. A raw U flip would produce .85 instead of .75.
        mesh.vertices[3] = {position = {1, 0, 0}, uv = {.70, .70}, part = .Wing}
        mesh.vertices[4] = {position = {1, 1, 0}, uv = {.70, .80}, part = .Wing}
        mesh.vertices[5] = {position = {1, 0, 1}, uv = {.80, .70}, part = .Wing}
        mesh.triangles[0] = {0, 1, 2}
        mesh.triangles[1] = {3, 4, 5}

        found, mirrored_part, mirrored_uv := vehicle_paint_mirror_uv_mesh(
            &mesh,
            {-1, .25, .25},
            .Wing,
        )
        testing.expect(t, found)
        testing.expect(t, mirrored_part == .Wing)
        testing.expect(t, math.abs(mirrored_uv[0] - .725) < .001)
        testing.expect(t, math.abs(mirrored_uv[1] - .725) < .001)
        testing.expect(t, math.abs(mirrored_uv[0] - .85) > .1)
    }

    @(test)
    vehicle_paint_clear_requires_a_timely_second_request :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        testing.expect(t, !vehicle_paint_clear_confirm(editor, 10))
        testing.expect(t, editor.vehicle_paint_clear_confirm_until == 12.5)
        testing.expect(t, vehicle_paint_clear_confirm(editor, 12))
        testing.expect(t, editor.vehicle_paint_clear_confirm_until == 0)

        testing.expect(t, !vehicle_paint_clear_confirm(editor, 20))
        testing.expect(t, !vehicle_paint_clear_confirm(editor, 23))
        testing.expect(t, editor.vehicle_paint_clear_confirm_until == 25.5)
    }

    @(test)
    vehicle_paint_sampler_requires_owned_paint_and_finds_nearest_palette_color :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        part := vehicles.Aircraft_Mesh_Part.Body
        texel_x, texel_y := 32, 24
        texel := texel_y * VEHICLE_PAINT_TEXTURE_WIDTH + texel_x
        uv := vehicle_paint_test_uv(texel_x, texel_y)

        _, sampled := vehicle_paint_sample_palette(editor, part, uv)
        testing.expect(t, !sampled)

        editor.vehicle_paint_texel_part[texel] = u8(part) + 1
        _, sampled = vehicle_paint_sample_palette(editor, part, uv)
        testing.expect(t, !sampled)

        pixels := vehicle_paint_pixels(editor)
        target := VEHICLE_PAINT_COLORS[6]
        vehicle_paint_set_texel(
            pixels,
            texel,
            {target.r + 2, target.g - 3, target.b + 1, 255},
        )
        palette_index: int
        palette_index, sampled = vehicle_paint_sample_palette(editor, part, uv)
        testing.expect(t, sampled)
        testing.expect(t, palette_index == 6)

        editor.vehicle_paint_texel_part[texel] = u8(vehicles.Aircraft_Mesh_Part.Wing) + 1
        _, sampled = vehicle_paint_sample_palette(editor, part, uv)
        testing.expect(t, !sampled)
    }

    @(test)
    vehicle_paint_brush_hardness_has_an_opaque_core_and_soft_edge :: proc(t: ^testing.T) {
        testing.expect(t, vehicle_paint_brush_coverage(0, .75) == 1)
        testing.expect(t, vehicle_paint_brush_coverage(.75, .75) == 1)
        testing.expect(t, math.abs(vehicle_paint_brush_coverage(.875, .75) - .5) < .001)
        testing.expect(t, vehicle_paint_brush_coverage(1, .75) == 0)
        testing.expect(t, vehicle_paint_brush_coverage(1.01, .75) == 0)
        testing.expect(t, vehicle_paint_brush_coverage(.99, 1) == 1)
    }

    @(test)
    vehicle_paint_working_settings_initialize_once :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        vehicle_paint_settings_initialize(editor)
        testing.expect(t, editor.vehicle_paint_settings_initialized)
        testing.expect(t, editor.vehicle_paint_tool == .Brush)
        testing.expect(t, editor.vehicle_paint_color == 0)
        testing.expect(t, editor.vehicle_paint_secondary_color == 13)
        testing.expect(t, editor.vehicle_paint_brush_radius == 14)
        testing.expect(t, editor.vehicle_paint_brush_hardness == .75)
        for enabled in editor.vehicle_paint_component_mask do testing.expect(t, enabled)

        editor.vehicle_paint_tool = .Gradient
        editor.vehicle_paint_color = 8
        editor.vehicle_paint_secondary_color = 2
        editor.vehicle_paint_brush_radius = 29
        editor.vehicle_paint_brush_hardness = .25
        editor.vehicle_paint_symmetry = true
        editor.vehicle_paint_component_mask[1] = false
        vehicle_paint_settings_initialize(editor)
        testing.expect(t, editor.vehicle_paint_tool == .Gradient)
        testing.expect(t, editor.vehicle_paint_color == 8)
        testing.expect(t, editor.vehicle_paint_secondary_color == 2)
        testing.expect(t, editor.vehicle_paint_brush_radius == 29)
        testing.expect(t, editor.vehicle_paint_brush_hardness == .25)
        testing.expect(t, editor.vehicle_paint_symmetry)
        testing.expect(t, !editor.vehicle_paint_component_mask[1])
    }

    @(test)
    vehicle_paint_drag_preview_benchmark :: proc(t: ^testing.T) {
        if os.get_env("ADRIATIC_PAINT_BENCH", context.temp_allocator) != "1" do return
        editor := new(Editor)
        defer free(editor)
        editor.vehicle_paint_brush_radius = 14
        part := vehicles.Aircraft_Mesh_Part.Body
        owner := u8(part) + 1
        for y in 64 ..< 192 {
            for x in 96 ..< 416 {
                editor.vehicle_paint_texel_part[y * VEHICLE_PAINT_TEXTURE_WIDTH + x] = owner
            }
        }
        start_uv := vehicle_paint_test_uv(120, 96)
        end_uv := vehicle_paint_test_uv(380, 160)
        primary := VEHICLE_PAINT_COLORS[0]
        secondary := VEHICLE_PAINT_COLORS[7]
        iterations := 30
        texels := vehicle_paint_connected_texels(editor, part, start_uv, false)

        start := time.tick_now()
        for _ in 0 ..< iterations {
            vehicle_paint_gradient_texels(editor, texels[:], start_uv, end_uv, primary, secondary)
            vehicle_paint_strip_texels(editor, texels[:], start_uv, end_uv, primary)
        }
        elapsed_ms := time.duration_seconds(time.tick_since(start)) * 1000
        fmt.printf(
            "PAINT_DRAG_BENCH iterations=%d region_texels=%d elapsed_ms=%.3f per_preview_ms=%.3f\n",
            iterations,
            320 * 128,
            elapsed_ms,
            elapsed_ms / f64(iterations * 2),
        )
        testing.expect(t, elapsed_ms > 0)
    }

    @(test)
    vehicle_paint_component_masks_toggle_solo_and_restore :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        editor.vehicle_paint_component_mask = {true, true, true, true, true}

        vehicle_paint_component_mask_activate(editor, 2, false)
        testing.expect(t, !editor.vehicle_paint_component_mask[2])
        testing.expect(t, editor.vehicle_paint_component == 2)

        vehicle_paint_component_mask_activate(editor, 3, true)
        for enabled, index in editor.vehicle_paint_component_mask {
            testing.expect(t, enabled == (index == 3))
        }
        testing.expect(t, editor.vehicle_paint_component == 3)

        vehicle_paint_component_mask_activate(editor, 3, true)
        for enabled in editor.vehicle_paint_component_mask do testing.expect(t, enabled)

        vehicle_paint_component_mask_activate(editor, 1, true)
        for enabled, index in editor.vehicle_paint_component_mask {
            testing.expect(t, enabled == (index == 1))
        }
    }
}
