package main

import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

when ODIN_TEST {
    @(test)
    mouse_preference_round_trips_and_rejects_invalid_data :: proc(t: ^testing.T) {
        // V3 and V4 intentionally share an ABI size. The loader must dispatch
        // by the embedded version instead of treating size as a unique tag.
        testing.expect_value(t, size_of(Mouse_Preference_File_V3), size_of(Mouse_Preference_File_V4))

        directory, directory_err := os.make_directory_temp("", "adriatic-mouse-*", context.allocator)
        testing.expect(t, directory_err == nil)
        if directory_err != nil do return
        path, path_err := strings.concatenate({directory, "/mouse.bin"}, context.allocator)
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
        source.mouse_fur = .Russet
        source.mouse_pattern = .Piebald
        // Exercise the highest appended enum value so preference validation
        // cannot silently reject newly added headgear.
        source.mouse_headgear = .Flat_Cap
        source.mouse_scarf_enabled = true
        source.mouse_scarf_color = {17, 83, 241, 255}
        source.gameplay_options = gameplay_options_default()
        source.gameplay_options.look_sensitivity = .021
        source.gameplay_options.sound_fx_level = .35
        source.gameplay_options.invert_look_y = true
        source.gameplay_options.show_hud = false
        source.gameplay_options.crunchiness = .P720
        source.gameplay_options.visual_style = .Dither
        source.gameplay_options.dither_mode = .Blue_Noise
        source.gameplay_options.hdr_exposure = false
        source.gameplay_options.theme_mode = .Dark
        source.gameplay_options.anti_aliasing = .MSAA_2X

        testing.expect(t, mouse_preference_save_to_path(source, path))
        testing.expect(t, mouse_preference_load_from_path(restored, path))
        testing.expect(t, restored.mouse_fur == source.mouse_fur)
        testing.expect(t, restored.mouse_pattern == source.mouse_pattern)
        testing.expect(t, restored.mouse_headgear == source.mouse_headgear)
        testing.expect(t, restored.mouse_scarf_enabled == source.mouse_scarf_enabled)
        testing.expect(t, restored.mouse_scarf_color == source.mouse_scarf_color)
        testing.expect(t, restored.gameplay_options == source.gameplay_options)

        bytes, read_err := os.read_entire_file(path, context.allocator)
        testing.expect(t, read_err == nil)
        if read_err != nil do return
        defer delete(bytes)
        saved_file := cast(^Mouse_Preference_File)raw_data(bytes)
        testing.expect_value(t, saved_file.header.magic, MOUSE_PREFERENCE_MAGIC_V5)
        testing.expect_value(t, saved_file.header.version, MOUSE_PREFERENCE_VERSION)
        testing.expect_value(t, saved_file.header.payload_size, u32(size_of(Mouse_Preference_Payload)))
        bytes[len(bytes) - 1] ~= 0xff
        testing.expect(t, os.write_entire_file(path, bytes) == nil)
        restored.mouse_fur = .White
        testing.expect(t, !mouse_preference_load_from_path(restored, path))
        testing.expect(t, restored.mouse_fur == .White)

        testing.expect(t, mouse_preference_save_to_path(source, path))
        invalid_bytes, invalid_read_err := os.read_entire_file(path, context.allocator)
        testing.expect(t, invalid_read_err == nil)
        if invalid_read_err == nil {
            defer delete(invalid_bytes)
            invalid_file := cast(^Mouse_Preference_File)raw_data(invalid_bytes)
            invalid_file.payload.visual_style = 255
            invalid_file.checksum = mouse_preference_checksum(&invalid_file.payload)
            testing.expect(t, os.write_entire_file(path, invalid_bytes) == nil)
            testing.expect(t, !mouse_preference_load_from_path(restored, path))
        }

        testing.expect(t, mouse_preference_save_to_path(source, path))
        header_bytes, header_read_err := os.read_entire_file(path, context.allocator)
        testing.expect(t, header_read_err == nil)
        if header_read_err == nil {
            defer delete(header_bytes)
            invalid_header := cast(^Mouse_Preference_File)raw_data(header_bytes)
            invalid_header.header.payload_size += 1
            testing.expect(t, os.write_entire_file(path, header_bytes) == nil)
            testing.expect(t, !mouse_preference_load_from_path(restored, path))
        }
    }

    @(test)
    mouse_preference_v4_migrates_to_v5_payload :: proc(t: ^testing.T) {
        directory, directory_err := os.make_directory_temp("", "adriatic-mouse-v4-*", context.allocator)
        testing.expect(t, directory_err == nil)
        if directory_err != nil do return
        path, path_err := strings.concatenate({directory, "/mouse.bin"}, context.allocator)
        testing.expect(t, path_err == nil)
        if path_err != nil do return
        defer {
            _ = os.remove(path)
            _ = os.remove(directory)
            delete(path)
            delete(directory)
        }

        legacy := Mouse_Preference_File_V4 {
            magic = MOUSE_PREFERENCE_MAGIC,
            version = 4,
            payload = {
                fur = u8(Mouse_Fur.Chestnut),
                pattern = u8(Mouse_Fur_Pattern.Solid),
                headgear = u8(Mouse_Accessory.Goggles),
                look_sensitivity = .018,
                sound_fx_level = .4,
                show_hud = true,
                crunchiness = u8(Crunchiness.P720),
                visual_style = u8(Visual_Style.Dither),
                dither_mode = u8(Dither_Mode.Bayer),
                hdr_exposure = true,
                theme_mode = u8(UI_Theme_Mode.Dark),
            },
        }
        legacy.checksum = mouse_preference_checksum_v5(&legacy.payload)
        legacy_bytes := mem.slice_ptr(cast([^]u8)&legacy, size_of(legacy))
        testing.expect(t, os.write_entire_file(path, legacy_bytes) == nil)

        restored := new(Editor)
        defer free(restored)
        testing.expect(t, mouse_preference_load_from_path(restored, path))
        testing.expect_value(t, restored.gameplay_options.look_sensitivity, f32(.018))
        testing.expect_value(t, restored.gameplay_options.visual_style, Visual_Style.Dither)
        testing.expect_value(t, restored.gameplay_options.theme_mode, UI_Theme_Mode.Dark)
        testing.expect_value(t, restored.gameplay_options.anti_aliasing, Anti_Aliasing.MSAA_4X)
    }


    @(test)
    mouse_preference_v3_migrates_dither_to_visual_style :: proc(t: ^testing.T) {
        directory, directory_err := os.make_directory_temp("", "adriatic-mouse-v3-*", context.allocator)
        testing.expect(t, directory_err == nil)
        if directory_err != nil do return
        path, path_err := strings.concatenate({directory, "/mouse.bin"}, context.allocator)
        testing.expect(t, path_err == nil)
        if path_err != nil do return
        defer {
            _ = os.remove(path)
            _ = os.remove(directory)
            delete(path)
            delete(directory)
        }

        legacy := Mouse_Preference_File_V3 {
            magic = MOUSE_PREFERENCE_MAGIC,
            version = 3,
            payload = {
                fur = u8(Mouse_Fur.Chestnut),
                pattern = u8(Mouse_Fur_Pattern.Solid),
                headgear = u8(Mouse_Accessory.Goggles),
                look_sensitivity = .012,
                sound_fx_level = .8,
                show_hud = true,
                crunchiness = u8(Crunchiness.P480),
                dither_mode = u8(Dither_Mode.Blue_Noise),
                hdr_exposure = true,
                theme_mode = u8(UI_Theme_Mode.Light),
            },
        }
        legacy.checksum = mouse_preference_checksum_v3(&legacy.payload)
        legacy_bytes := mem.slice_ptr(cast([^]u8)&legacy, size_of(legacy))
        testing.expect(t, os.write_entire_file(path, legacy_bytes) == nil)

        restored := new(Editor)
        defer free(restored)
        testing.expect(t, mouse_preference_load_from_path(restored, path))
        testing.expect_value(t, restored.gameplay_options.visual_style, Visual_Style.Dither)
        testing.expect_value(t, restored.gameplay_options.dither_mode, Dither_Mode.Blue_Noise)
    }
}
