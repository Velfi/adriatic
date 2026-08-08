package main

import terrain "../packages/terrain"
import "core:testing"

@(test)
building_tool_exposes_placeable_site_types :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    cases := [?]struct {
        kind:         Building_Generator_Kind,
        width, depth: f32,
    }{{.Windmill, 10, 10}, {.Patio, 8, 6}, {.Garden, 12, 10}, {.Cemetery, 30, 36}, {.Plaza, 18, 16}}
    for item in cases {
        building_generator_select_kind(editor, item.kind)
        testing.expect_value(t, editor.building_generator_kind, item.kind)
        testing.expect_value(t, editor.building_generator_width, item.width)
        testing.expect_value(t, editor.building_generator_depth, item.depth)
    }
}

@(test)
building_tool_site_markers_are_distinct_from_ordinary_foliage :: proc(t: ^testing.T) {
    ordinary := terrain.Structure {
        kind = .Foliage,
    }
    marker := ordinary
    marker.group_id = BUILDING_GENERATOR_SITE_GROUP_TAG | u64(Building_Generator_Kind.Garden)
    testing.expect(t, !building_generator_site_marker(ordinary))
    testing.expect(t, building_generator_site_marker(marker))
    testing.expect(t, building_generator_is_site_kind(.Patio))
    testing.expect(t, building_generator_is_site_kind(.Garden))
    testing.expect(t, building_generator_is_site_kind(.Cemetery))
    testing.expect(t, building_generator_is_site_kind(.Plaza))
    testing.expect(t, !building_generator_is_site_kind(.Windmill))
}
