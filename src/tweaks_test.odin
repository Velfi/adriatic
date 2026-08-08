package main

import "core:os"
import "core:strings"
import "core:testing"
import tweak_package "zelda_engine:tweak"

when ODIN_TEST {
    @(test)
    developer_time_controls_round_trip_in_tweak_toml :: proc(t: ^testing.T) {
        resolved_path, path_ok := tweak_file_path(context.temp_allocator)
        testing.expect(t, path_ok)
        testing.expect(t, strings.has_suffix(resolved_path, "/Adriatic/adriatic.tweak.toml"))

        directory, directory_err := os.make_directory_temp("", "adriatic-tweak-time-*", context.allocator)
        testing.expect(t, directory_err == nil)
        if directory_err != nil do return
        path, path_err := strings.concatenate({directory, "/adriatic.tweak.toml"}, context.allocator)
        testing.expect(t, path_err == nil)
        if path_err != nil do return
        defer {
            _ = os.remove(path)
            _ = os.remove(directory)
            delete(path)
            delete(directory)
        }

        source := tweak_default_state()
        source.time_scale = 4.5
        source.atmosphere.paused = true
        source.player_outline = {
            enabled  = true,
            width    = 3,
            strength = .45,
            color    = {.2, .3, .4},
        }
        testing.expect(t, tweak_package.save(path, TWEAK_FILE_VERSION, &source) == nil)

        restored := tweak_default_state()
        result := tweak_package.load(path, TWEAK_FILE_VERSION, &restored, "Adriatic tweaks")
        defer tweak_package.destroy_load_result(&result)
        testing.expect(t, result.loaded_sections > 0)
        testing.expect(t, restored.time_scale == 4.5)
        testing.expect(t, restored.atmosphere.paused)
        testing.expect(t, restored.player_outline.enabled)
        testing.expect(t, restored.player_outline.width == 3)
        testing.expect(t, restored.player_outline.strength == .45)
        testing.expect(t, restored.player_outline.color == [3]f32{.2, .3, .4})
    }

    @(test)
    player_outline_defaults_survive_missing_tweak_section :: proc(t: ^testing.T) {
        directory, directory_err := os.make_directory_temp("", "adriatic-tweak-outline-*", context.allocator)
        testing.expect(t, directory_err == nil)
        if directory_err != nil do return
        path, path_err := strings.concatenate({directory, "/adriatic.tweak.toml"}, context.allocator)
        testing.expect(t, path_err == nil)
        if path_err != nil do return
        defer {
            _ = os.remove(path)
            _ = os.remove(directory)
            delete(path)
            delete(directory)
        }
        testing.expect(t, os.write_entire_file_from_string(path, "version = 1\n") == nil)
        restored := tweak_default_state()
        result := tweak_package.load(path, TWEAK_FILE_VERSION, &restored, "Adriatic tweaks")
        defer tweak_package.destroy_load_result(&result)
        testing.expect(t, !restored.player_outline.enabled)
        testing.expect(t, restored.player_outline.width == 1)
        testing.expect(t, restored.player_outline.strength == .8)
        testing.expect(t, restored.player_outline.color == [3]f32{35 / 255.0, 32 / 255.0, 30 / 255.0})
    }
}
