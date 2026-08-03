package main

import vehicles "../packages/vehicles"
import "core:testing"

@(test)
vehicle_paint_postale_flaps_have_paintable_texels :: proc(t: ^testing.T) {
    editor := new(Editor)
    defer free(editor)
    defer vehicle_paint_storage_destroy(editor)
    mesh := vehicles.postale_mesh()
    defer free(mesh)

    vehicle_paint_build_texel_parts(editor, mesh)
    left_owner := u8(vehicles.Aircraft_Mesh_Part.Left_Flap) + 1
    right_owner := u8(vehicles.Aircraft_Mesh_Part.Right_Flap) + 1
    fillet_owner := u8(vehicles.Aircraft_Mesh_Part.Wing_Root_Fillet) + 1
    left_texels, right_texels, fillet_texels := 0, 0, 0
    for owner in editor.vehicle_paint_texel_part {
        if owner == left_owner do left_texels += 1
        if owner == right_owner do right_texels += 1
        if owner == fillet_owner do fillet_texels += 1
    }

    testing.expect(t, vehicle_paint_part_is_paintable(.Left_Flap))
    testing.expect(t, vehicle_paint_part_is_paintable(.Right_Flap))
    testing.expect(t, left_texels > 0)
    testing.expect(t, right_texels > 0)
    testing.expect(t, vehicle_paint_part_is_paintable(.Wing_Root_Fillet))
    testing.expect_value(t, vehicle_paint_component_for_part(.Wing_Root_Fillet), 1)
    testing.expect(t, fillet_texels > 0)
}
