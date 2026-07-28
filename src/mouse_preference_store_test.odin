package main

import "core:os"
import "core:strings"
import "core:testing"

when ODIN_TEST {
    @(test)
    mouse_preference_round_trips_and_rejects_invalid_data :: proc(t: ^testing.T) {
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
        source.gameplay_options.invert_look_y = true
        source.gameplay_options.show_hud = false
        source.gameplay_options.crunchiness = .P720
        source.gameplay_options.dither_mode = .Blue_Noise
        source.gameplay_options.hdr_exposure = false
        source.gameplay_options.theme_mode = .Dark

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
        bytes[len(bytes) - 1] ~= 0xff
        testing.expect(t, os.write_entire_file(path, bytes) == nil)
        restored.mouse_fur = .White
        testing.expect(t, !mouse_preference_load_from_path(restored, path))
        testing.expect(t, restored.mouse_fur == .White)
    }
}
