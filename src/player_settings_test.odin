package main

import "core:math"
import "core:os"
import "core:strings"
import "core:testing"

when ODIN_TEST {
    @(test)
    controller_deadzone_shapes_stick_and_trigger_inputs :: proc(t: ^testing.T) {
        settings := gameplay_options_default()
        settings.controller_stick_deadzone = .2
        settings.controller_trigger_deadzone = .1
        controller_deadzone_apply(settings)
        testing.expect(t, shape_flight_axis(.19, settings.controller_stick_deadzone) == 0)
        testing.expect(t, math.abs(shape_flight_axis(.6, settings.controller_stick_deadzone) - .5) < .001)
        testing.expect(t, shape_flight_axis(.09, settings.controller_trigger_deadzone) == 0)
        testing.expect(t, math.abs(shape_flight_axis(.55, settings.controller_trigger_deadzone) - .5) < .001)
    }

    @(test)
    player_settings_round_trips_as_toml :: proc(t: ^testing.T) {
        directory, directory_err := os.make_directory_temp("", "adriatic-player-settings-*", context.allocator)
        testing.expect(t, directory_err == nil)
        if directory_err != nil do return
        toml_path, toml_path_err := strings.concatenate({directory, "/player-settings.toml"}, context.allocator)
        testing.expect(t, toml_path_err == nil)
        if toml_path_err != nil do return
        defer {
            _ = os.remove(toml_path)
            _ = os.remove(directory)
            delete(toml_path)
            delete(directory)
        }

        source := new(Editor)
        restored := new(Editor)
        defer free(source)
        defer free(restored)
        source.gameplay_options = gameplay_options_default()
        source.gameplay_options.look_sensitivity = .021
        source.gameplay_options.sound_fx_level = .35
        source.gameplay_options.controller_stick_deadzone = .27
        source.gameplay_options.controller_trigger_deadzone = .11
        source.gameplay_options.invert_look_y = true
        source.gameplay_options.crunchiness = .P720
        source.gameplay_options.visual_style = .Dither
        source.gameplay_options.dither_mode = .Blue_Noise
        source.gameplay_options.theme_mode = .Dark
        source.gameplay_options.anti_aliasing = .MSAA_2X
        source.gameplay_options.vsync = false
        source.mouse_fur = .Russet
        source.mouse_pattern = .Piebald
        source.mouse_headgear = .Flat_Cap
        source.mouse_scarf_enabled = true
        source.mouse_scarf_color = {17, 83, 241, 255}

        testing.expect(t, player_settings_save_to_path(source, toml_path))
        bytes, read_err := os.read_entire_file(toml_path, context.allocator)
        testing.expect(t, read_err == nil)
        if read_err != nil do return
        defer delete(bytes)
        text := string(bytes)
        testing.expect(t, strings.contains(text, "\"version\" = 1"))
        testing.expect(t, strings.contains(text, "[\"gameplay\"]"))
        testing.expect(t, strings.contains(text, "\"controller_stick_deadzone\" = 0.27"))
        testing.expect(t, strings.contains(text, "[\"mouse\"]"))
        testing.expect(t, player_settings_load_from_path(restored, toml_path))
        testing.expect(t, restored.gameplay_options == source.gameplay_options)
        testing.expect(t, restored.mouse_fur == source.mouse_fur)
        testing.expect(t, restored.mouse_pattern == source.mouse_pattern)
        testing.expect(t, restored.mouse_headgear == source.mouse_headgear)
        testing.expect(t, restored.mouse_scarf_enabled == source.mouse_scarf_enabled)
        testing.expect(t, restored.mouse_scarf_color == source.mouse_scarf_color)
    }

    @(test)
    player_settings_rejects_invalid_toml_without_mutating_editor :: proc(t: ^testing.T) {
        directory, directory_err := os.make_directory_temp("", "adriatic-player-settings-invalid-*", context.allocator)
        testing.expect(t, directory_err == nil)
        if directory_err != nil do return
        path, path_err := strings.concatenate({directory, "/player-settings.toml"}, context.allocator)
        testing.expect(t, path_err == nil)
        if path_err != nil do return
        defer {
            _ = os.remove(path)
            _ = os.remove(directory)
            delete(path)
            delete(directory)
        }

        invalid := "version = 999\n[gameplay]\ncontroller_stick_deadzone = 2.0\n"
        testing.expect(t, os.write_entire_file(path, transmute([]u8)invalid) == nil)
        editor := new(Editor)
        defer free(editor)
        editor.gameplay_options = gameplay_options_default()
        before := editor.gameplay_options
        testing.expect(t, !player_settings_load_from_path(editor, path))
        testing.expect(t, editor.gameplay_options == before)
    }

    @(test)
    player_settings_migrates_legacy_binary_to_toml :: proc(t: ^testing.T) {
        directory, directory_err := os.make_directory_temp("", "adriatic-player-settings-migrate-*", context.allocator)
        testing.expect(t, directory_err == nil)
        if directory_err != nil do return
        binary_path, binary_path_err := strings.concatenate({directory, "/legacy.bin"}, context.allocator)
        testing.expect(t, binary_path_err == nil)
        toml_path, toml_path_err := strings.concatenate({directory, "/player-settings.toml"}, context.allocator)
        testing.expect(t, toml_path_err == nil)
        if binary_path_err != nil || toml_path_err != nil do return
        defer {
            _ = os.remove(binary_path)
            _ = os.remove(toml_path)
            _ = os.remove(directory)
            delete(binary_path)
            delete(toml_path)
            delete(directory)
        }

        source := new(Editor)
        migrated := new(Editor)
        restored := new(Editor)
        defer free(source)
        defer free(migrated)
        defer free(restored)
        source.gameplay_options = gameplay_options_default()
        source.gameplay_options.look_sensitivity = .019
        source.gameplay_options.visual_style = .Dither
        source.gameplay_options.dither_mode = .Bayer
        source.mouse_fur = .Cream
        source.mouse_pattern = .Masked
        source.mouse_headgear = .Goggles

        testing.expect(t, mouse_preference_save_to_path(source, binary_path))
        testing.expect(t, mouse_preference_load_from_path(migrated, binary_path))
        testing.expect(t, player_settings_save_to_path(migrated, toml_path))
        testing.expect(t, player_settings_load_from_path(restored, toml_path))
        testing.expect(t, restored.gameplay_options == migrated.gameplay_options)
        testing.expect(t, restored.mouse_fur == migrated.mouse_fur)
        testing.expect(t, restored.mouse_pattern == migrated.mouse_pattern)
        testing.expect(t, restored.mouse_headgear == migrated.mouse_headgear)
    }
}
