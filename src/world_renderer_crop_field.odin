package main

import "core:math"

import terrain "../packages/terrain"
import canvas2d "zelda_engine:canvas2d"

CROP_FIELD_SHORE_CLEARANCE :: f32(6)
CROP_FIELD_DRY_LAND_CLEARANCE :: f32(.35)

world_crop_field_volume_value :: proc(structure: terrain.Structure, local_x, local_z: f32) -> f32 {
    half_width := max(structure.width * .5, f32(.01))
    half_depth := max(structure.depth * .5, f32(.01))
    normalized_x := local_x / half_width
    normalized_z := local_z / half_depth
    radius := f32(math.sqrt(f64(normalized_x * normalized_x + normalized_z * normalized_z)))

    // Treat the authored formation as a low plant volume, not a rectangular
    // decal. Several broad, deterministic undulations turn its horizontal
    // cross-section into one coherent planted mass while retaining the volume's
    // width, depth, rotation, and seed as the authoring controls.
    angle := f32(math.atan2(f64(normalized_z), f64(normalized_x)))
    phase := f32(structure.seed % 1021) * .0137
    boundary :=
        f32(.84) +
        f32(math.sin(f64(angle * 3 + phase))) * .075 +
        f32(math.sin(f64(angle * 5 - phase * .61))) * .045 +
        f32(math.sin(f64(angle * 7 + phase * .37))) * .025
    return boundary - radius
}

world_crop_field_volume_contains :: proc(structure: terrain.Structure, local_x, local_z, _: f32) -> bool {
    return world_crop_field_volume_value(structure, local_x, local_z) >= 0
}

world_crop_field_volume_edge :: proc(from, to: [2]f32, from_value, to_value: f32) -> [2]f32 {
    denominator := from_value - to_value
    t := abs(denominator) <= 1e-6 ? f32(.5) : clamp(from_value / denominator, 0, 1)
    return from + (to - from) * t
}

world_crop_field_clipped_cell :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    local: [4][2]f32,
    color: canvas2d.Color,
) {
    values: [4]f32
    for point, index in local {
        values[index] = world_crop_field_volume_value(structure, point.x, point.y)
    }

    polygon: [8][2]f32
    polygon_count := 0
    previous := local[3]
    previous_value := values[3]
    previous_inside := previous_value >= 0
    for current, index in local {
        current_value := values[index]
        current_inside := current_value >= 0
        if current_inside != previous_inside {
            polygon[polygon_count] = world_crop_field_volume_edge(previous, current, previous_value, current_value)
            polygon_count += 1
        }
        if current_inside {
            polygon[polygon_count] = current
            polygon_count += 1
        }
        previous = current
        previous_value = current_value
        previous_inside = current_inside
    }
    if polygon_count < 3 do return

    a := world_crop_field_point(structure, project, polygon[0].x, polygon[0].y)
    for index in 1 ..< polygon_count - 1 {
        b := world_crop_field_point(structure, project, polygon[index].x, polygon[index].y)
        c := world_crop_field_point(structure, project, polygon[index + 1].x, polygon[index + 1].y)
        world_triangle(a, b, c, color)
    }
}

world_crop_field_is_inland :: proc(project: ^terrain.Project, x, z, clearance: f32) -> bool {
    if project == nil do return false
    for z_direction in -1 ..= 1 {
        for x_direction in -1 ..= 1 {
            sample_x := x + f32(x_direction) * clearance
            sample_z := z + f32(z_direction) * clearance
            land_height, _, land_found := terrain.sample_land(project, 0, sample_x, sample_z)
            if !land_found ||
               land_height <= project.sea_level + CROP_FIELD_DRY_LAND_CLEARANCE ||
               terrain.active_waterway_at(project, 0, sample_x, sample_z) {
                return false
            }
        }
    }
    return true
}

world_crop_field_point :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    local_x, local_z: f32,
) -> [3]f32 {
    x, z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
    ground_y := structure.base_y
    if project != nil do ground_y = terrain.sample_surface_height(project, 0, x, z)
    wave := f32(math.sin(f64(x * .31 + z * .17 + f32(structure.seed) * .013))) * structure.height * .035
    return {x, ground_y + structure.height + wave, z}
}

world_crop_field :: proc(structure: terrain.Structure, project: ^terrain.Project, lod: Structure_LOD = .Near) {
    if structure.width <= 0 || structure.depth <= 0 do return
    shadow_first := len(world_renderer.vertices)
    defer world_register_shadow_caster(shadow_first)

    target_cell := lod == .Near ? f32(2) : lod == .Medium ? f32(4) : f32(8)
    columns := clamp(int(math.ceil(f64(structure.width / target_cell))), 1, 128)
    rows := clamp(int(math.ceil(f64(structure.depth / target_cell))), 1, 128)
    step_x, step_z := structure.width / f32(columns), structure.depth / f32(rows)
    half_width, half_depth := structure.width * .5, structure.depth * .5
    wheat_light := canvas2d.Color{181, 150, 61, 255}
    wheat_dark := canvas2d.Color{174, 143, 57, 255}

    for row in 0 ..< rows {
        for column in 0 ..< columns {
            x0 := -half_width + f32(column) * step_x
            x1 := x0 + step_x
            z0 := -half_depth + f32(row) * step_z
            z1 := z0 + step_z
            center_x, center_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                (x0 + x1) * .5,
                (z0 + z1) * .5,
                structure.rotation,
            )
            cell_radius := f32(math.sqrt(f64(step_x * step_x + step_z * step_z))) * .5
            if !world_crop_field_is_inland(project, center_x, center_z, CROP_FIELD_SHORE_CLEARANCE + cell_radius) {
                continue
            }
            color := ((column + row + int(structure.seed)) & 1) == 0 ? wheat_light : wheat_dark
            world_crop_field_clipped_cell(structure, project, {{x0, z0}, {x0, z1}, {x1, z1}, {x1, z0}}, color)
        }
    }
}
