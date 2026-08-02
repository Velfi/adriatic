package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

world_architecture_mixed_use_entrances :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    opening_layout: ^architecture.Opening_Layout,
    mixed_use, has_entrance: bool,
    facade_style: int,
) {
    if mixed_use && has_entrance {
        // Keep residential circulation independent from the shop. Each flank
        // gets a narrow stair door toward the street, so an attached row still
        // exposes at least one apartment entrance at its open end.
        for side in -1 ..= 1 {
            if side == 0 do continue
            side_f := f32(side)
            side_face := side < 0 ? architecture.Face.Left : architecture.Face.Right
            if opening_layout == nil ||
               !architecture.opening_layout_contains(opening_layout, side_face, .Service_Door, 0, 0) {
                continue
            }
            side_y := structure.base_y + 1.62
            side_local_x := side_f * (structure.width * .5 + .13)
            side_local_z := structure.depth * .20
            clearance := world_architecture_mixed_use_side_clearance(structure, project, side)
            opposite_clearance := world_architecture_mixed_use_side_clearance(structure, project, -side)
            // Prefer all genuinely open sides. If both nominal approaches are
            // tight, retain exactly the side with more clearance so upstairs
            // apartments can never lose their independent entrance entirely.
            if clearance < .85 &&
               (opposite_clearance >= .85 ||
                       clearance < opposite_clearance ||
                       (clearance == opposite_clearance && side != (structure.seed & 1 == 0 ? -1 : 1))) {
                continue
            }
            threshold_x, threshold_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_f * (structure.width * .5 + 1.15),
                side_local_z,
                structure.rotation,
            )
            side_x, side_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x,
                side_local_z,
                structure.rotation,
            )
            side_yaw := structure.rotation + side_f * math.PI * .5
            side_door_color := facade_style == 2 ? canvas2d.Color{74, 104, 105, 255} : canvas2d.Color{67, 91, 91, 255}
            world_box_rotated({side_x, side_y, side_z}, {1.65, 3.05, .20}, side_yaw, side_door_color)
            // Four shallow panels and a real lever distinguish the private
            // upstairs entrance from a blank service door. Keep the relief
            // modest: the glazed shopfront remains the street's focal point.
            panel_color := formation_face_color(side_door_color, math.PI, 1)
            for panel_row in 0 ..< 2 {
                panel_y := structure.base_y + .88 + f32(panel_row) * .98
                for panel_column in -1 ..= 1 {
                    if panel_column == 0 do continue
                    panel_local_z := side_local_z + f32(panel_column) * .39
                    panel_x, panel_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        side_local_x + side_f * .125,
                        panel_local_z,
                        structure.rotation,
                    )
                    world_box_rotated({panel_x, panel_y, panel_z}, {.54, .62, .035}, side_yaw, panel_color)
                }
            }
            lever_x, lever_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .24,
                side_local_z - .54,
                structure.rotation,
            )
            world_box_rotated(
                {lever_x, structure.base_y + 1.52, lever_z},
                {.08, .08, .16},
                side_yaw,
                {211, 171, 91, 255},
            )
            for jamb in -1 ..= 1 {
                if jamb == 0 do continue
                jamb_x, jamb_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    side_local_x,
                    side_local_z + f32(jamb) * .93,
                    structure.rotation,
                )
                world_box_rotated({jamb_x, side_y, jamb_z}, {.13, 3.30, .14}, side_yaw, {202, 184, 145, 255})
            }
            lintel_x, lintel_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x,
                side_local_z,
                structure.rotation,
            )
            world_box_rotated(
                {lintel_x, structure.base_y + 3.30, lintel_z},
                {1.95, .15, .14},
                side_yaw,
                {202, 184, 145, 255},
            )
            transom_x, transom_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .13,
                side_local_z,
                structure.rotation,
            )
            world_box_rotated(
                {transom_x, structure.base_y + 2.72, transom_z},
                {1.24, .34, .045},
                side_yaw,
                {48, 78, 78, 255},
            )
            step_x, step_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .46,
                side_local_z,
                structure.rotation,
            )
            world_box_rotated(
                {step_x, structure.base_y + .08, step_z},
                {2.05, .16, .74},
                side_yaw,
                {166, 143, 112, 255},
            )
            // A short run of limestone flags connects the private landing to
            // the public shop pavement. Generate it only after the clearance
            // test above, so a suppressed door never leaves an orphan path.
            path_end_z := structure.depth * .5 + .72
            path_span := max(path_end_z - side_local_z, f32(1.6))
            path_paver_length := path_span / 4 * .86
            for path_paver in 0 ..< 4 {
                paver_local_z := side_local_z + path_span * (f32(path_paver) + .5) / 4
                paver_x, paver_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    side_local_x + side_f * .92,
                    paver_local_z,
                    structure.rotation,
                )
                paver_ground := structure.base_y
                if project != nil {
                    paver_ground = terrain.sample_height(project, 0, paver_x, paver_z)
                }
                paver_color :=
                    path_paver % 2 == 0 ? canvas2d.Color{184, 171, 143, 255} : canvas2d.Color{166, 153, 128, 255}
                world_box_rotated(
                    {paver_x, paver_ground + .045, paver_z},
                    {1.48, .09, path_paver_length},
                    structure.rotation,
                    paver_color,
                )
            }
            canopy_x, canopy_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .46,
                side_local_z,
                structure.rotation,
            )
            world_box_rotated(
                {canopy_x, structure.base_y + 3.48, canopy_z},
                {2.20, .16, .82},
                side_yaw,
                facade_style == 2 ? canvas2d.Color{105, 143, 151, 255} : canvas2d.Color{178, 103, 72, 255},
            )
            // A compact stair-step glyph on the canopy fascia identifies this
            // as access to upper dwellings, not a secondary shop entrance.
            // Keep it symbolic so it remains legible across localized worlds.
            stair_sign_x, stair_sign_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .89,
                side_local_z,
                structure.rotation,
            )
            world_box_rotated(
                {stair_sign_x, structure.base_y + 3.47, stair_sign_z},
                {.76, .34, .045},
                side_yaw,
                {60, 76, 74, 255},
            )
            for stair_mark in 0 ..< 3 {
                mark_local_z := side_local_z - .20 + f32(stair_mark) * .20
                stair_mark_x, stair_mark_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    side_local_x + side_f * .925,
                    mark_local_z,
                    structure.rotation,
                )
                world_box_rotated(
                    {stair_mark_x, structure.base_y + 3.40 + f32(stair_mark) * .07, stair_mark_z},
                    {.13, .07 + f32(stair_mark) * .025, .025},
                    side_yaw,
                    {211, 171, 91, 255},
                )
            }
            // A narrow stairwell light above the portal makes the apartment
            // circulation read vertically instead of as a second ground-floor
            // shop entrance.
            stair_window_y := structure.base_y + 4.62
            stair_frame_x, stair_frame_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .14,
                side_local_z,
                structure.rotation,
            )
            world_box_rotated(
                {stair_frame_x, stair_window_y, stair_frame_z},
                {1.18, 1.48, .16},
                side_yaw,
                {72, 83, 78, 255},
            )
            stair_glass_x, stair_glass_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .235,
                side_local_z,
                structure.rotation,
            )
            world_box_rotated_material(
                {stair_glass_x, stair_window_y, stair_glass_z},
                {.90, 1.20, .035},
                side_yaw,
                {184, 132, 68, 255},
                .Emissive,
            )
            stair_panel_x, stair_panel_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .25,
                side_local_z,
                structure.rotation,
            )
            world_glass_panel(
                {stair_panel_x, stair_window_y, stair_panel_z},
                .84,
                1.14,
                side_yaw,
                {71, 101, 101, 255},
                .72,
            )
            world_box_rotated(
                {stair_glass_x, stair_window_y, stair_glass_z},
                {.055, 1.20, .045},
                side_yaw,
                {191, 174, 139, 255},
            )
            world_box_rotated(
                {stair_glass_x, stair_window_y, stair_glass_z},
                {.90, .055, .045},
                side_yaw,
                {191, 174, 139, 255},
            )
            lamp_x, lamp_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .30,
                side_local_z + .68,
                structure.rotation,
            )
            world_box_rotated({lamp_x, structure.base_y + 2.28, lamp_z}, {.22, .34, .16}, side_yaw, {72, 65, 56, 255})
            light_x, light_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .40,
                side_local_z + .68,
                structure.rotation,
            )
            world_box_rotated_material(
                {light_x, structure.base_y + 2.28, light_z},
                {.12, .19, .035},
                side_yaw,
                {255, 172, 66, 255},
                .Emissive,
            )
            world_municipal_light_pool(
                threshold_x,
                structure.base_y,
                threshold_z,
                project,
                .09,
                1.20,
                .76,
                side_yaw,
                30,
                1,
                {255, 178, 78, 255},
            )
            number_x, number_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x + side_f * .28,
                side_local_z - .58,
                structure.rotation,
            )
            world_box_rotated(
                {number_x, structure.base_y + 2.15, number_z},
                {.28, .20, .04},
                side_yaw,
                {215, 193, 139, 255},
            )
            // Twin dark strokes are a compact "upper dwellings" marker at
            // streetscape scale, backed by the lit stair window above.
            for address_mark in -1 ..= 1 {
                if address_mark == 0 do continue
                mark_x, mark_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    side_local_x + side_f * .31,
                    side_local_z - .58 + f32(address_mark) * .055,
                    structure.rotation,
                )
                world_box_rotated(
                    {mark_x, structure.base_y + 2.15, mark_z},
                    {.035, .11, .025},
                    side_yaw,
                    {76, 67, 54, 255},
                )
            }
        }
    }
}
