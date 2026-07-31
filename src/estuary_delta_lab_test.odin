package main

import estuaries "../packages/estuaries"
import "core:testing"

@(test)
estuary_delta_lab_is_registered_and_seed_target_is_parseable :: proc(t: ^testing.T) {
    definition := lab_scene_find("estuary-delta")
    testing.expect(t, definition != nil)
    testing.expect(t, definition.configure == estuary_delta_lab_configure)
    testing.expect(t, definition.process_input == estuary_delta_lab_process_input)
    testing.expect(t, definition.draw_ui == estuary_delta_lab_draw_ui)
    request, ok := lab_scene_request_from_args([]string{"adriatic", "--lab", "estuary-delta", "0x1234"})
    testing.expect(t, ok)
    testing.expect(t, request.definition == definition)
    testing.expect_value(t, request.target, "0x1234")
}

@(test)
estuary_delta_lab_defaults_match_generator_contract :: proc(t: ^testing.T) {
    config := estuaries.default_config()
    testing.expect_value(t, config.archetype, estuaries.Archetype.Tidal_Estuary)
    testing.expect_value(t, config.branching, f32(.55))
    testing.expect_value(t, config.mouth_width, f32(.22))
    testing.expect_value(t, config.sediment_load, f32(.60))
    testing.expect_value(t, config.relief, f32(12))
    testing.expect_value(t, config.mean_sea_level, f32(0))
    testing.expect_value(t, config.tidal_range, f32(1.4))
}
