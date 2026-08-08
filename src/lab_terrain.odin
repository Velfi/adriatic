package main

import terrain "../packages/terrain"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

// A renderer-owned ground plane for presentation labs. The clipmap mesh still
// follows the camera, but every generated vertex uses this constant surface;
// no editable terrain page or sculptable chunk owns the result.
Lab_Flat_Terrain :: struct {
    enabled: bool,
    height:  f32,
    color:   canvas2d.Color,
}

// Labs usually need one focused terrain patch, not an entire authored world.
// The sampler is only called inside the configured patch; the shared loader
// initializes every clipmap level and supplies a cheap, explicit outside fill.
Lab_Terrain_Sample :: struct {
    height:   f32,
    material: f32,
}

Lab_Terrain_Sampler :: proc(editor: ^Editor, world_x, world_z: f32) -> Lab_Terrain_Sample

Lab_Terrain_Config :: struct {
    center_x:         f32,
    center_z:         f32,
    half_extent_x:    f32,
    half_extent_z:    f32,
    sea_level:        f32,
    outside_height:   f32,
    outside_material: f32,
    // Zero entries use the standard 1, 2, 4... metre clipmap spacing.
    cell_sizes:       [terrain.CLIPMAP_LEVELS]f32,
}

lab_terrain_config_valid :: proc(config: Lab_Terrain_Config) -> bool {
    values := [?]f32 {
        config.center_x,
        config.center_z,
        config.half_extent_x,
        config.half_extent_z,
        config.sea_level,
        config.outside_height,
        config.outside_material,
    }
    for value in values {
        if value != value || math.is_inf_f32(value) do return false
    }
    if config.half_extent_x < 0 || config.half_extent_z < 0 do return false
    for cell_size in config.cell_sizes {
        if cell_size != cell_size || math.is_inf_f32(cell_size) || cell_size < 0 do return false
    }
    return true
}

lab_terrain_load :: proc(editor: ^Editor, config: Lab_Terrain_Config, sampler: Lab_Terrain_Sampler = nil) -> bool {
    if editor == nil || !lab_terrain_config_valid(config) do return false
    editor.lab_flat_terrain = {}
    editor.project.sea_level = config.sea_level
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        data := &editor.project.levels[level_index]
        cell_size := config.cell_sizes[level_index]
        if cell_size <= 0 do cell_size = terrain.FINE_CELL_SIZE * f32(math.pow(2, f64(level_index)))
        data.cell_size = cell_size
        half_grid := f32(terrain.TERRAIN_RESOLUTION - 1) * .5 * cell_size
        data.origin_x = config.center_x - half_grid
        data.origin_z = config.center_z - half_grid
        for z in 0 ..< terrain.TERRAIN_RESOLUTION {
            world_z := data.origin_z + f32(z) * cell_size
            inside_z := math.abs(world_z - config.center_z) <= config.half_extent_z
            for x in 0 ..< terrain.TERRAIN_RESOLUTION {
                index := terrain.sample_index(x, z)
                data.heights[index] = config.outside_height
                data.material[index] = config.outside_material
                if sampler == nil || !inside_z do continue
                world_x := data.origin_x + f32(x) * cell_size
                if math.abs(world_x - config.center_x) > config.half_extent_x do continue
                sample := sampler(editor, world_x, world_z)
                data.heights[index] = sample.height
                data.material[index] = sample.material
            }
        }
    }
    editor.project.revision += 1
    world_terrain_invalidate_all(editor)
    return true
}

lab_flat_terrain_load :: proc(
    editor: ^Editor,
    height: f32 = 0,
    material: f32 = 0,
    color: canvas2d.Color = {116, 137, 96, 255},
) -> bool {
    if editor == nil || height != height || math.is_inf_f32(height) do return false
    // Keep the ordinary terrain samplers useful for actors and props inside a
    // lab while the renderer supplies the genuinely unbounded visual plane.
    if !lab_terrain_load(editor, {
        sea_level        = height - 64,
        outside_height   = height,
        outside_material = material,
    }) {
        return false
    }
    editor.lab_flat_terrain = {
        enabled = true,
        height  = height,
        color   = color,
    }
    return true
}
