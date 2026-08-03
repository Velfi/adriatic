package main

import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import canvas2d "zelda_engine:canvas2d"

when ODIN_TEST {
    vehicle_paint_test_uv :: proc(x, y: int) -> [2]f32 {
        return {(f32(x) + .5) / VEHICLE_PAINT_TEXTURE_WIDTH, (f32(y) + .5) / VEHICLE_PAINT_TEXTURE_HEIGHT}
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
        defer {
            vehicle_paint_storage_destroy(source)
            vehicle_paint_storage_destroy(restored)
            free(source)
            free(restored)
        }
        testing.expect(t, vehicle_paint_storage_ensure(source))
        testing.expect(t, vehicle_paint_storage_ensure(restored))
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
        defer vehicle_paint_storage_destroy(editor)
        vehicle_paint_history_init(editor)
        defer vehicle_paint_history_destroy(editor)
        editor.vehicle_paint_component_mask = {true, true, true, true, true}
        editor.vehicle_paint_brush_radius = 4
        editor.vehicle_paint_brush_strength = 1
        part := vehicles.Aircraft_Mesh_Part.Body
        owner := u8(part) + 1
        pixels := vehicle_paint_pixels(editor)

        // Bucket covers every enabled component, including disconnected UV
        // islands, while leaving masked components untouched.
        for y in 10 ..= 19 {
            for x in 10 ..= 19 {
                editor.vehicle_paint_texel_part[y * VEHICLE_PAINT_TEXTURE_WIDTH + x] = owner
            }
            for x in 22 ..= 29 {
                editor.vehicle_paint_texel_part[y * VEHICLE_PAINT_TEXTURE_WIDTH + x] = owner
            }
        }
        red := canvas2d.Color{220, 20, 30, 255}
        blue := canvas2d.Color{20, 60, 220, 255}
        masked_part := vehicles.Aircraft_Mesh_Part.Wing
        masked_texel := 14 * VEHICLE_PAINT_TEXTURE_WIDTH + 32
        editor.vehicle_paint_texel_part[masked_texel] = u8(masked_part) + 1
        editor.vehicle_paint_component_mask[vehicle_paint_component_for_part(masked_part)] = false
        vehicle_paint_history_capture(editor)
        vehicle_paint_bucket(editor, part, vehicle_paint_test_uv(14, 14), red)
        testing.expect(t, vehicle_paint_history_commit(editor))
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 14) * 4] == red.r)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 24) * 4] == red.r)
        testing.expect(t, pixels[masked_texel * 4 + 3] == 0)

        vehicle_paint_history_capture(editor)
        vehicle_paint_pattern(editor, part, vehicle_paint_test_uv(24, 14), red, blue)
        testing.expect(t, vehicle_paint_history_commit(editor))
        first_pattern := pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 24) * 4]
        second_pattern := pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 28) * 4]
        testing.expect(t, first_pattern != second_pattern)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 14) * 4] == red.r)
        testing.expect(t, pixels[masked_texel * 4 + 3] == 0)

        vehicle_paint_history_undo(editor)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 24) * 4] == red.r)
        vehicle_paint_history_undo(editor)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 14) * 4 + 3] == 0)
        vehicle_paint_history_redo(editor)
        vehicle_paint_history_redo(editor)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 14) * 4] == red.r)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 24) * 4 + 3] == 255)

        // Gradient produces both endpoint colors but cannot leave the island.
        vehicle_paint_gradient(editor, part, vehicle_paint_test_uv(10, 14), vehicle_paint_test_uv(19, 14), red, blue)
        left := (14 * VEHICLE_PAINT_TEXTURE_WIDTH + 10) * 4
        right := (14 * VEHICLE_PAINT_TEXTURE_WIDTH + 19) * 4
        testing.expect(t, pixels[left] > pixels[right])
        testing.expect(t, pixels[left + 2] < pixels[right + 2])

        // Shape and strip are hard edged and ownership clipped.
        vehicle_paint_shape(editor, part, vehicle_paint_test_uv(14, 14), blue)
        testing.expect(t, pixels[(14 * VEHICLE_PAINT_TEXTURE_WIDTH + 14) * 4 + 2] == blue.b)
        disconnected_near_strip := 12 * VEHICLE_PAINT_TEXTURE_WIDTH + 22
        vehicle_paint_set_texel(pixels, disconnected_near_strip, {}, 0)
        vehicle_paint_strip(editor, part, vehicle_paint_test_uv(10, 12), vehicle_paint_test_uv(19, 12), red)
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
    vehicle_paint_uv_mask_includes_triangle_edge_texels :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        defer vehicle_paint_storage_destroy(editor)
        mesh := new(vehicles.Aircraft_Mesh)
        defer free(mesh)
        part := vehicles.Aircraft_Mesh_Part.Body
        mesh.vertex_count = 3
        mesh.triangle_count = 1
        mesh.vertices[0] = {
            uv   = {9.9 / VEHICLE_PAINT_TEXTURE_WIDTH, 10.0 / VEHICLE_PAINT_TEXTURE_HEIGHT},
            part = part,
        }
        mesh.vertices[1] = {
            uv   = {14.0 / VEHICLE_PAINT_TEXTURE_WIDTH, 10.0 / VEHICLE_PAINT_TEXTURE_HEIGHT},
            part = part,
        }
        mesh.vertices[2] = {
            uv   = {9.9 / VEHICLE_PAINT_TEXTURE_WIDTH, 14.0 / VEHICLE_PAINT_TEXTURE_HEIGHT},
            part = part,
        }
        mesh.triangles[0] = {0, 1, 2}

        vehicle_paint_build_texel_parts(editor, mesh)

        owner := u8(part) + 1
        testing.expect(t, editor.vehicle_paint_texel_part[10 * VEHICLE_PAINT_TEXTURE_WIDTH + 9] == owner)
        testing.expect(t, editor.vehicle_paint_texel_part[10 * VEHICLE_PAINT_TEXTURE_WIDTH + 8] == 0)
    }

    @(test)
    vehicle_paint_uv_mask_excludes_protected_materials :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        defer vehicle_paint_storage_destroy(editor)
        mesh := new(vehicles.Aircraft_Mesh)
        defer free(mesh)
        mesh.vertex_count = 6
        mesh.triangle_count = 2
        for index in 0 ..< 3 do mesh.vertices[index].part = .Wheel
        mesh.vertices[0].uv = {.10, .10}
        mesh.vertices[1].uv = {.20, .10}
        mesh.vertices[2].uv = {.10, .20}
        for index in 3 ..< 6 do mesh.vertices[index].part = .Glass
        mesh.vertices[3].uv = {.30, .30}
        mesh.vertices[4].uv = {.40, .30}
        mesh.vertices[5].uv = {.30, .40}
        mesh.triangles[0] = {0, 1, 2}
        mesh.triangles[1] = {3, 4, 5}

        vehicle_paint_build_texel_parts(editor, mesh)

        testing.expect(t, !vehicle_paint_part_is_paintable(.Wheel))
        testing.expect(t, !vehicle_paint_part_is_paintable(.Glass))
        testing.expect(t, vehicle_paint_part_is_paintable(.Body))
        for owner in editor.vehicle_paint_texel_part do testing.expect(t, owner == 0)
    }

    @(test)
    vehicle_paint_symmetry_resolves_the_opposite_surface_not_flipped_uv :: proc(t: ^testing.T) {
        mesh := new(vehicles.Aircraft_Mesh)
        defer free(mesh)
        mesh.vertex_count = 6
        mesh.triangle_count = 2
        mesh.vertices[0] = {
            position = {-1, 0, 0},
            uv       = {.10, .10},
            part     = .Wing,
        }
        mesh.vertices[1] = {
            position = {-1, 1, 0},
            uv       = {.10, .20},
            part     = .Wing,
        }
        mesh.vertices[2] = {
            position = {-1, 0, 1},
            uv       = {.20, .10},
            part     = .Wing,
        }
        // The opposite triangle deliberately lives in an unrelated area of
        // the packed atlas. A raw U flip would produce .85 instead of .75.
        mesh.vertices[3] = {
            position = {1, 0, 0},
            uv       = {.70, .70},
            part     = .Wing,
        }
        mesh.vertices[4] = {
            position = {1, 1, 0},
            uv       = {.70, .80},
            part     = .Wing,
        }
        mesh.vertices[5] = {
            position = {1, 0, 1},
            uv       = {.80, .70},
            part     = .Wing,
        }
        mesh.triangles[0] = {0, 1, 2}
        mesh.triangles[1] = {3, 4, 5}

        found, mirrored_part, mirrored_uv := vehicle_paint_mirror_uv_mesh(mesh, {-1, .25, .25}, .Wing)
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
        defer vehicle_paint_storage_destroy(editor)
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
        defer vehicle_paint_storage_destroy(editor)
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
        vehicle_paint_set_texel(pixels, texel, {target.r + 2, target.g - 3, target.b + 1, 255})
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
    vehicle_paint_shade_ramps_are_asymmetric_and_respect_existing_colors :: proc(t: ^testing.T) {
        for base in VEHICLE_PAINT_COLORS {
            ramp := vehicle_paint_shade_ramp(base)
            testing.expect(t, ramp[2] == base)
            for index in 1 ..< len(ramp) {
                previous_value := int(ramp[index - 1].r) + int(ramp[index - 1].g) + int(ramp[index - 1].b)
                value := int(ramp[index].r) + int(ramp[index].g) + int(ramp[index].b)
                testing.expect(t, value > previous_value)
            }
            cool := canvas2d.Color{12, 22, 39, 255}
            warm := canvas2d.Color{255, 248, 224, 255}
            bcr, bcg, bcb := int(base.r) - int(cool.r), int(base.g) - int(cool.g), int(base.b) - int(cool.b)
            scr, scg, scb := int(ramp[0].r) - int(cool.r), int(ramp[0].g) - int(cool.g), int(ramp[0].b) - int(cool.b)
            bwr, bwg, bwb := int(base.r) - int(warm.r), int(base.g) - int(warm.g), int(base.b) - int(warm.b)
            hwr, hwg, hwb := int(ramp[4].r) - int(warm.r), int(ramp[4].g) - int(warm.g), int(ramp[4].b) - int(warm.b)
            base_cool_distance := bcr * bcr + bcg * bcg + bcb * bcb
            shadow_cool_distance := scr * scr + scg * scg + scb * scb
            base_warm_distance := bwr * bwr + bwg * bwg + bwb * bwb
            highlight_warm_distance := hwr * hwr + hwg * hwg + hwb * hwb
            testing.expect(t, shadow_cool_distance < base_cool_distance)
            testing.expect(t, highlight_warm_distance < base_warm_distance)
        }

        base := VEHICLE_PAINT_COLORS[0]
        ramp := vehicle_paint_shade_ramp(base)
        low_gap := int(ramp[1].r) - int(ramp[0].r)
        high_gap := int(ramp[4].r) - int(ramp[3].r)
        testing.expect(t, low_gap != high_gap)

        darker, changed := vehicle_paint_shade_step({base.r, base.g, base.b, 255}, false)
        testing.expect(t, changed)
        testing.expect(t, darker == ramp[1])
        lighter, lighter_changed := vehicle_paint_shade_step({darker.r, darker.g, darker.b, 255}, true)
        testing.expect(t, lighter_changed)
        testing.expect(t, lighter == base)
        custom := canvas2d.Color{0, 255, 0, 255}
        custom_darker, custom_changed := vehicle_paint_shade_step({custom.r, custom.g, custom.b, 255}, false)
        testing.expect(t, custom_changed)
        testing.expect(t, custom_darker == vehicle_paint_shade_ramp(custom)[1])

        other_base := VEHICLE_PAINT_COLORS[6]
        other_darker, other_changed := vehicle_paint_shade_step({other_base.r, other_base.g, other_base.b, 255}, false)
        testing.expect(t, other_changed)
        testing.expect(t, other_darker == vehicle_paint_shade_ramp(other_base)[1])
    }

    @(test)
    vehicle_paint_working_settings_initialize_once :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        defer vehicle_paint_storage_destroy(editor)
        vehicle_paint_settings_initialize(editor)
        testing.expect(t, editor.vehicle_paint_settings_initialized)
        testing.expect(t, editor.vehicle_paint_tool == .Brush)
        testing.expect(t, editor.vehicle_paint_color == 0)
        testing.expect(t, editor.vehicle_paint_secondary_color == 13)
        testing.expect(t, editor.vehicle_paint_pattern == 0)
        testing.expect(t, editor.vehicle_paint_pattern_size == 32)
        testing.expect(t, editor.vehicle_paint_pattern_rotation == 0)
        testing.expect(t, editor.vehicle_paint_shape_kind == 0)
        testing.expect(t, editor.vehicle_paint_shape_size == 32)
        testing.expect(t, editor.vehicle_paint_shape_rotation == 0)
        testing.expect(t, editor.vehicle_paint_brush_radius == 14)
        testing.expect(t, editor.vehicle_paint_brush_hardness == .75)
        testing.expect(t, editor.vehicle_paint_brush_strength == .75)
        for enabled in editor.vehicle_paint_component_mask do testing.expect(t, enabled)

        editor.vehicle_paint_tool = .Gradient
        editor.vehicle_paint_color = 8
        editor.vehicle_paint_secondary_color = 2
        editor.vehicle_paint_pattern = 9
        editor.vehicle_paint_pattern_size = 96
        editor.vehicle_paint_pattern_rotation = 45
        editor.vehicle_paint_shape_kind = 5
        editor.vehicle_paint_shape_size = 96
        editor.vehicle_paint_shape_rotation = 30
        editor.vehicle_paint_brush_radius = 29
        editor.vehicle_paint_brush_hardness = .25
        editor.vehicle_paint_brush_strength = .5
        editor.vehicle_paint_symmetry = true
        editor.vehicle_paint_component_mask[1] = false
        vehicle_paint_settings_initialize(editor)
        testing.expect(t, editor.vehicle_paint_tool == .Gradient)
        testing.expect(t, editor.vehicle_paint_color == 8)
        testing.expect(t, editor.vehicle_paint_secondary_color == 2)
        testing.expect(t, editor.vehicle_paint_pattern == 9)
        testing.expect(t, editor.vehicle_paint_pattern_size == 96)
        testing.expect(t, editor.vehicle_paint_pattern_rotation == 45)
        testing.expect(t, editor.vehicle_paint_shape_kind == 5)
        testing.expect(t, editor.vehicle_paint_shape_size == 96)
        testing.expect(t, editor.vehicle_paint_shape_rotation == 30)
        testing.expect(t, editor.vehicle_paint_brush_radius == 29)
        testing.expect(t, editor.vehicle_paint_brush_hardness == .25)
        testing.expect(t, editor.vehicle_paint_brush_strength == .5)
        testing.expect(t, editor.vehicle_paint_symmetry)
        testing.expect(t, !editor.vehicle_paint_component_mask[1])
    }

    @(test)
    vehicle_paint_pattern_palette_contains_twelve_two_color_patterns :: proc(t: ^testing.T) {
        testing.expect(t, len(VEHICLE_PAINT_PATTERN_NAMES) == 12)
        for pattern in 0 ..< len(VEHICLE_PAINT_PATTERN_NAMES) {
            has_primary, has_secondary := false, false
            for y in 0 ..< 32 {
                for x in 0 ..< 32 {
                    if vehicle_paint_pattern_secondary(pattern, x, y, 8) {
                        has_secondary = true
                    } else {
                        has_primary = true
                    }
                }
            }
            testing.expect(t, has_primary)
            testing.expect(t, has_secondary)
        }
    }

    @(test)
    vehicle_paint_pattern_edges_are_antialiased_and_rotation_changes_sampling :: proc(t: ^testing.T) {
        edge := vehicle_paint_pattern_coverage(1, 4, 8, 16, 1, 0)
        testing.expect(t, math.abs(edge - .5) < .001)

        unrotated := vehicle_paint_pattern_coverage(1, 4, 4, 16, 1, 0)
        quarter_turn := vehicle_paint_pattern_coverage(1, 4, 4, 16, 0, 1)
        testing.expect(t, unrotated == 0)
        testing.expect(t, quarter_turn == 1)
    }

    @(test)
    vehicle_paint_touchpad_orbit_distinguishes_precise_scroll_from_mouse_wheel :: proc(t: ^testing.T) {
        testing.expect(t, vehicle_paint_touchpad_orbit_gesture({.35, 0}))
        testing.expect(t, vehicle_paint_touchpad_orbit_gesture({0, .125}))
        testing.expect(t, !vehicle_paint_touchpad_orbit_gesture({0, 1}))
        testing.expect(t, !vehicle_paint_touchpad_orbit_gesture({0, -2}))
    }

    @(test)
    vehicle_paint_shape_palette_has_distinct_rotatable_silhouettes :: proc(t: ^testing.T) {
        testing.expect(t, len(VEHICLE_PAINT_SHAPE_NAMES) == 6)
        for kind in 0 ..< len(VEHICLE_PAINT_SHAPE_NAMES) {
            testing.expect(t, vehicle_paint_shape_contains(kind, 0, 0, 10))
            testing.expect(t, !vehicle_paint_shape_contains(kind, 11, 11, 10))
        }
        testing.expect(t, vehicle_paint_shape_contains(2, 9, 9, 10))
        testing.expect(t, !vehicle_paint_shape_contains(1, 9, 9, 10))
        testing.expect(t, vehicle_paint_shape_contains(3, 5, -8, 10, 0))
        testing.expect(t, !vehicle_paint_shape_contains(3, 5, -8, 10, 180))
    }

    @(test)
    vehicle_paint_drag_preview_benchmark :: proc(t: ^testing.T) {
        if os.get_env("ADRIATIC_PAINT_BENCH", context.temp_allocator) != "1" do return
        editor := new(Editor)
        defer free(editor)
        defer vehicle_paint_storage_destroy(editor)
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
        defer vehicle_paint_storage_destroy(editor)
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

    @(test)
    vehicle_paint_classifies_exterior_panels_and_control_groups :: proc(t: ^testing.T) {
        // Authored red metal is used for structural exterior panels and must
        // accept the player's livery. Non-paint materials remain protected.
        testing.expect(t, vehicle_paint_part_is_paintable(.Red_Paint))
        testing.expect(t, !vehicle_paint_part_is_paintable(.Wheel))
        testing.expect(t, !vehicle_paint_part_is_paintable(.Glass))
        testing.expect(t, !vehicle_paint_part_is_paintable(.Propeller_Blur))
        testing.expect(t, !vehicle_paint_part_is_paintable(.Marking))
        testing.expect(t, !vehicle_paint_part_is_paintable(.Strap))

        wing_parts := [5]vehicles.Aircraft_Mesh_Part{.Wing, .Left_Flap, .Right_Flap, .Left_Aileron, .Right_Aileron}
        for part in wing_parts do testing.expect_value(t, vehicle_paint_component_for_part(part), 1)

        rotor_parts := [6]vehicles.Aircraft_Mesh_Part {
            .Left_Rotor,
            .Right_Rotor,
            .Rear_Rotor,
            .Mk2_Rear_Rotor,
            .Rotor_Blade,
            .Rotor_Tip,
        }
        for part in rotor_parts do testing.expect_value(t, vehicle_paint_component_for_part(part), 3)
        testing.expect_value(t, vehicle_paint_component_for_part(.Lift_Frame), 4)
    }

    @(test)
    vehicle_paint_postale_exposes_all_structural_components :: proc(t: ^testing.T) {
        mesh := vehicles.postale_mesh()
        defer free(mesh)

        found: [5]bool
        protected_markings := 0
        for triangle in mesh.triangles[:mesh.triangle_count] {
            a := mesh.vertices[triangle.a]
            b := mesh.vertices[triangle.b]
            c := mesh.vertices[triangle.c]
            // Paint ownership reads the first corner, so mixed-part triangles
            // would silently make some visible faces unreachable.
            testing.expect(t, a.part == b.part && a.part == c.part)
            if vehicle_paint_part_is_paintable(a.part) {
                found[vehicle_paint_component_for_part(a.part)] = true
            } else if a.part == .Marking {
                protected_markings += 1
            }
        }
        for component_present in found do testing.expect(t, component_present)
        // The cowling livery band remains authored/protected, while wheel
        // hubs and covers are no longer hidden behind the Marking tag.
        testing.expect(t, protected_markings > 0)
    }

    @(test)
    vehicle_paint_fill_and_gradient_scopes_distinguish_face_angle_from_component :: proc(t: ^testing.T) {
        up := [3]f32{0, 1, 0}
        shallow := [3]f32{0, .94, .342}
        steep := [3]f32{0, .5, .866}

        testing.expect(t, vehicle_paint_scope_matches(.Wing, .Wing, shallow, up, 1, false))
        testing.expect(t, !vehicle_paint_scope_matches(.Wing, .Wing, steep, up, 1, false))
        testing.expect(t, !vehicle_paint_scope_matches(.Left_Flap, .Wing, up, up, 1, false))

        // Component scope crosses mesh-part and face-angle boundaries, but
        // never leaks from the wing assembly into another semantic component.
        testing.expect(t, vehicle_paint_scope_matches(.Left_Flap, .Wing, steep, up, 1, true))
        testing.expect(t, vehicle_paint_scope_matches(.Right_Aileron, .Wing, steep, up, 1, true))
        testing.expect(t, !vehicle_paint_scope_matches(.Body, .Wing, up, up, 1, true))
        testing.expect(t, !vehicle_paint_scope_matches(.Glass, .Wing, up, up, 1, true))
    }

    @(test)
    vehicle_paint_direct_mask_gates_paint_and_supports_clear_invert :: proc(t: ^testing.T) {
        editor := new(Editor)
        defer free(editor)
        defer vehicle_paint_storage_destroy(editor)
        editor.vehicle_paint_component_mask = {true, true, true, true, true}
        editor.vehicle_paint_selection_texels = make([]u8, VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_HEIGHT)
        defer delete(editor.vehicle_paint_selection_texels)
        owner := u8(vehicles.Aircraft_Mesh_Part.Body) + 1
        selected_texel := 12 * VEHICLE_PAINT_TEXTURE_WIDTH + 12
        blocked_texel := 12 * VEHICLE_PAINT_TEXTURE_WIDTH + 13
        editor.vehicle_paint_texel_part[selected_texel] = owner
        editor.vehicle_paint_texel_part[blocked_texel] = owner
        editor.vehicle_paint_selection_texels[selected_texel] = 1
        editor.vehicle_paint_selection_active = true

        color := canvas2d.Color{210, 44, 30, 255}
        vehicle_paint_bucket(editor, .Body, {}, color)
        pixels := vehicle_paint_pixels(editor)
        testing.expect_value(t, pixels[selected_texel * 4], color.r)
        testing.expect_value(t, pixels[blocked_texel * 4 + 3], u8(0))

        vehicle_paint_selection_invert(editor)
        testing.expect_value(t, editor.vehicle_paint_selection_texels[selected_texel], u8(0))
        testing.expect_value(t, editor.vehicle_paint_selection_texels[blocked_texel], u8(1))
        vehicle_paint_selection_clear(editor)
        testing.expect(t, !editor.vehicle_paint_selection_active)
        testing.expect(t, vehicle_paint_texel_selected(editor, selected_texel))
        testing.expect(t, vehicle_paint_texel_selected(editor, blocked_texel))
    }
}
