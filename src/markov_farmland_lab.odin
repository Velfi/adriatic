package main

import atmosphere "../packages/atmosphere"
import farmland "../packages/farmland"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:strconv"
import rl "zelda_engine:canvas2d"

MARKOV_FARMLAND_DEFAULT_SEED :: u32(0x4641524d)
MARKOV_FARMLAND_ORIGIN_X :: f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
MARKOV_FARMLAND_ORIGIN_Z :: MARKOV_FARMLAND_ORIGIN_X + terrain.DEFAULT_TOWN_OFFSET
FARM_INSTANCE_CAPACITY :: 16

Farm_Instance :: struct {
    plan:     farmland.Plan,
    origin_x: f32,
    origin_z: f32,
    yaw:      f32,
}

markov_farmland_plan: farmland.Plan
farmland_render_origin_x := MARKOV_FARMLAND_ORIGIN_X
farmland_render_origin_z := MARKOV_FARMLAND_ORIGIN_Z
farmland_render_yaw := f32(-.14)
farmland_render_preview := false

farmland_warp_grid :: proc(grid_x, grid_z: f32) -> (f32, f32) {
    // Shared low-frequency displacement keeps adjacent parcels watertight
    // while bending their common boundaries. Two cross-coupled waves prevent
    // the result from becoming a uniformly sheared checkerboard.
    warp_x := math.sin(grid_z * .43 + math.sin(grid_x * .19) * .8) * .52 + math.sin(grid_z * .15 - grid_x * .09) * .22
    warp_z := math.sin(grid_x * .37 + math.sin(grid_z * .17) * .7) * .46 + math.sin(grid_x * .13 + grid_z * .08) * .20
    return grid_x + warp_x, grid_z + warp_z
}

farmland_color :: proc(crop: farmland.Crop, tint: f32) -> rl.Color {
    base: rl.Color
    switch crop {
    case .Wheat:
        base = {190, 157, 72, 255}
    case .Olive:
        base = {91, 112, 67, 255}
    case .Vineyard:
        base = {108, 126, 62, 255}
    case .Fallow:
        base = {137, 101, 65, 255}
    case .Clover:
        base = {75, 132, 72, 255}
    }
    warm := rl.Color{202, 177, 103, 255}
    return color_lerp(base, warm, tint * .12)
}

farmland_world_point :: proc(editor: ^Editor, grid_x, grid_z: f32, lift: f32) -> third_person.Vec3 {
    warped_x, warped_z := farmland_warp_grid(grid_x, grid_z)
    local_x := (warped_x - f32(farmland.GRID_WIDTH) * .5) * farmland.CELL_METERS
    local_z := (warped_z - f32(farmland.GRID_HEIGHT) * .5) * farmland.CELL_METERS
    // A slight landscape-scale yaw prevents the farm envelope from aligning
    // with the world axes even where the boundary displacement crosses zero.
    cosine, sine := math.cos(farmland_render_yaw), math.sin(farmland_render_yaw)
    x := farmland_render_origin_x + local_x * cosine - local_z * sine
    z := farmland_render_origin_z + local_x * sine + local_z * cosine
    y := terrain.sample_height(&editor.project, 0, x, z) + lift
    return {x, y, z}
}

farmland_patch :: proc(editor: ^Editor, x0, z0, x1, z1: f32, color: rl.Color, lift: f32 = .16) {
    a := farmland_world_point(editor, x0, z0, lift)
    b := farmland_world_point(editor, x0, z1, lift)
    c := farmland_world_point(editor, x1, z1, lift)
    d := farmland_world_point(editor, x1, z0, lift)
    world_quad(a, b, c, d, color)
}

farmland_hedgerow :: proc(editor: ^Editor, x0, z0, x1, z1: f32, seed: u32, detail_fade: f32) {
    if detail_fade <= .18 || farmland_render_preview do return
    grid_dx, grid_dz := x1 - x0, z1 - z0
    grid_length := f32(math.sqrt(f64(grid_dx * grid_dx + grid_dz * grid_dz)))
    segment_count := max(int(math.ceil(f64(grid_length * farmland.CELL_METERS / 12))), 1)
    for segment in 0 ..< segment_count {
        t0 := f32(segment) / f32(segment_count)
        t1 := f32(segment + 1) / f32(segment_count)
        segment_start := farmland_world_point(editor, x0 + grid_dx * t0, z0 + grid_dz * t0, 0)
        segment_finish := farmland_world_point(editor, x0 + grid_dx * t1, z0 + grid_dz * t1, 0)
        dx, dz := segment_finish.x - segment_start.x, segment_finish.z - segment_start.z
        segment_length := f32(math.sqrt(f64(dx * dx + dz * dz)))
        center_x := (segment_start.x + segment_finish.x) * .5
        center_z := (segment_start.z + segment_finish.z) * .5
        mixed := farmland.mix(seed ~ u32(segment + 1) * u32(0x9e3779b9))
        hedge_height := 2.25 + f32((mixed >> 16) & 255) / 255 * .55
        hedge_depth := 1.65 + f32((mixed >> 24) & 255) / 255 * .30
        structure := terrain.Structure {
            center_x = center_x,
            center_z = center_z,
            width    = segment_length + .7,
            depth    = hedge_depth,
            base_y   = terrain.sample_height(&editor.project, 0, center_x, center_z) + .08,
            height   = hedge_height,
            rotation = math.atan2(dz, dx),
            kind     = .Foliage,
            seed     = mixed,
        }

        // Use the foliage tool's recessed binder and overlapping scalloped
        // crown lobes. Short terrain-fitted segments prevent long hedges from
        // bridging across the rolling landscape.
        world_foliage_lobe(
            structure,
            0,
            0,
            structure.width * .88,
            structure.depth * .76,
            structure.height * .44,
            0,
            true,
            19,
            0,
            false,
        )
        for lobe in 0 ..< 3 {
            fraction := (f32(lobe) + .5) / 3
            along := (fraction - .5) * structure.width * .78
            outward := lobe & 1 == 0 ? f32(math.PI * .5) : f32(math.PI * 1.5)
            world_foliage_lobe(
                structure,
                along,
                0,
                structure.width / 3 * 1.72,
                structure.depth,
                structure.height * (.68 + f32(lobe & 1) * .06),
                0,
                true,
                lobe,
                outward,
                true,
            )
        }
    }
}

farmland_render_plan :: proc(editor: ^Editor, plan: ^farmland.Plan) {
    if editor == nil || plan == nil || !plan.valid do return
    center_height := terrain.sample_height(&editor.project, 0, farmland_render_origin_x, farmland_render_origin_z)
    altitude := max(editor.camera_pose.position.y - center_height, f32(0))
    detail_fade := 1 - clamp((altitude - 42) / 115, f32(0), f32(1))
    // Keep the inexpensive 5 m terrain mesh at every altitude. Coarsening to
    // 20 m saved only a few hundred quads, but bridged over hill curvature and
    // let the ground punch through. Detail still halves aloft via row collapse.
    step := 1
    verge := f32(.10)
    row_subdivisions := detail_fade > .62 ? 2 : 1

    for parcel in plan.parcels[:plan.parcel_count] {
        solid := farmland_color(parcel.crop, parcel.tint)
        if farmland_render_preview {
            solid = color_lerp(solid, rl.Color{128, 211, 166, 255}, .42)
        }
        for z := parcel.min_z; z < parcel.max_z; z += step {
            for x := parcel.min_x; x < parcel.max_x; x += step {
                x1, z1 := min(x + step, parcel.max_x), min(z + step, parcel.max_z)
                for row in 0 ..< row_subdivisions {
                    stripe_index := (parcel.row_axis_x ? z : x) * row_subdivisions + row
                    stripe := f32((stripe_index + int(parcel.phase * 7)) & 1)
                    detailed := color_lerp(solid, {226, 202, 125, 255}, .07 + stripe * .14)
                    if parcel.crop == .Fallow {
                        detailed = color_lerp(solid, {95, 73, 51, 255}, .04 + stripe * .18)
                    }
                    color := color_lerp(solid, detailed, detail_fade)
                    inset_x0 := f32(x)
                    inset_z0 := f32(z)
                    inset_x1 := f32(x1)
                    inset_z1 := f32(z1)
                    if parcel.row_axis_x {
                        row_depth := f32(z1 - z) / f32(row_subdivisions)
                        inset_z0 = f32(z) + f32(row) * row_depth
                        inset_z1 = inset_z0 + row_depth
                    } else {
                        row_width := f32(x1 - x) / f32(row_subdivisions)
                        inset_x0 = f32(x) + f32(row) * row_width
                        inset_x1 = inset_x0 + row_width
                    }
                    if x == parcel.min_x do inset_x0 += verge
                    if z == parcel.min_z do inset_z0 += verge
                    if x1 == parcel.max_x do inset_x1 -= verge
                    if z1 == parcel.max_z do inset_z1 -= verge
                    farmland_patch(editor, inset_x0, inset_z0, inset_x1, inset_z1, color)
                }
            }
        }

        // One narrow, terrain-sampled seam per parcel side gives the patchwork
        // depth at walking height. From the air these collapse into simple dark
        // boundaries without requiring foliage cards or a separate material.
        hedge := color_lerp(rl.Color{48, 78, 43, 255}, solid, 1 - detail_fade * .72)
        edge := f32(.055)
        farmland_patch(
            editor,
            f32(parcel.min_x) - edge,
            f32(parcel.min_z),
            f32(parcel.min_x) + edge,
            f32(parcel.max_z),
            hedge,
            .18,
        )
        farmland_patch(
            editor,
            f32(parcel.max_x) - edge,
            f32(parcel.min_z),
            f32(parcel.max_x) + edge,
            f32(parcel.max_z),
            hedge,
            .18,
        )
        farmland_patch(
            editor,
            f32(parcel.min_x),
            f32(parcel.min_z) - edge,
            f32(parcel.max_x),
            f32(parcel.min_z) + edge,
            hedge,
            .18,
        )
        farmland_patch(
            editor,
            f32(parcel.min_x),
            f32(parcel.max_z) - edge,
            f32(parcel.max_x),
            f32(parcel.max_z) + edge,
            hedge,
            .18,
        )
    }

    // The same generated parcel boundaries drive the foliage layer. Drawing
    // only each parcel's minimum edges (plus the outer maximum edges) avoids
    // doubling shared hedges, while deterministic card jitter breaks up the
    // silhouette. Cards disappear before the aerial solid-color LOD.
    for parcel, parcel_index in plan.parcels[:plan.parcel_count] {
        hedge_seed := plan.seed ~ u32(parcel_index + 1) * u32(0x85ebca6b)
        if farmland.mix(hedge_seed) & 3 != 0 {
            farmland_hedgerow(
                editor,
                f32(parcel.min_x),
                f32(parcel.min_z),
                f32(parcel.min_x),
                f32(parcel.max_z),
                hedge_seed,
                detail_fade,
            )
        }
        if farmland.mix(hedge_seed ~ u32(0xc2b2ae35)) & 3 != 0 {
            farmland_hedgerow(
                editor,
                f32(parcel.min_x),
                f32(parcel.min_z),
                f32(parcel.max_x),
                f32(parcel.min_z),
                hedge_seed ~ u32(0xc2b2ae35),
                detail_fade,
            )
        }
        if parcel.max_x == farmland.GRID_WIDTH {
            farmland_hedgerow(
                editor,
                f32(parcel.max_x),
                f32(parcel.min_z),
                f32(parcel.max_x),
                f32(parcel.max_z),
                hedge_seed ~ u32(0x27d4eb2f),
                detail_fade,
            )
        }
        if parcel.max_z == farmland.GRID_HEIGHT {
            farmland_hedgerow(
                editor,
                f32(parcel.min_x),
                f32(parcel.max_z),
                f32(parcel.max_x),
                f32(parcel.max_z),
                hedge_seed ~ u32(0x165667b1),
                detail_fade,
            )
        }
    }

    // A narrow L-shaped farm lane gives every composition a practical access
    // spine. It stays just a handful of terrain-conforming quads at every LOD.
    track := color_lerp(rl.Color{151, 119, 75, 255}, rl.Color{176, 151, 101, 255}, 1 - detail_fade)
    track_half_width := f32(.16)
    track_x := f32(farmland.GRID_WIDTH / 2)
    track_z := f32(farmland.GRID_HEIGHT / 2)
    for z := 0; z < farmland.GRID_HEIGHT; z += 5 {
        farmland_patch(
            editor,
            track_x - track_half_width,
            f32(z),
            track_x + track_half_width,
            f32(min(z + 5, farmland.GRID_HEIGHT)),
            track,
            .19,
        )
    }
    for x := 0; x < farmland.GRID_WIDTH / 2; x += 5 {
        farmland_patch(
            editor,
            f32(x),
            track_z - track_half_width,
            f32(min(x + 5, farmland.GRID_WIDTH / 2)),
            track_z + track_half_width,
            track,
            .19,
        )
    }
}

world_markov_farmland :: proc(editor: ^Editor) {
    farmland_render_origin_x = MARKOV_FARMLAND_ORIGIN_X
    farmland_render_origin_z = MARKOV_FARMLAND_ORIGIN_Z
    farmland_render_yaw = -.14
    farmland_render_preview = false
    farmland_render_plan(editor, &markov_farmland_plan)
}

world_authored_farmland :: proc(editor: ^Editor) {
    if editor == nil do return
    for &instance in editor.farms[:editor.farm_count] {
        farmland_render_origin_x = instance.origin_x
        farmland_render_origin_z = instance.origin_z
        farmland_render_yaw = instance.yaw
        farmland_render_preview = false
        farmland_render_plan(editor, &instance.plan)
    }
    if editor.farm_paint_mode && editor.farm_preview_valid {
        farmland_render_origin_x = editor.farm_preview.origin_x
        farmland_render_origin_z = editor.farm_preview.origin_z
        farmland_render_yaw = editor.farm_preview.yaw
        farmland_render_preview = true
        farmland_render_plan(editor, &editor.farm_preview.plan)
        farmland_render_preview = false
    }
}

markov_farmland_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    seed := MARKOV_FARMLAND_DEFAULT_SEED
    if parsed, ok := strconv.parse_int(target); ok && parsed >= 0 && parsed <= 0xffffffff {
        seed = u32(parsed)
    }
    markov_farmland_plan = farmland.generate(seed, context.temp_allocator)
    if !farmland.validate(&markov_farmland_plan) do return false

    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 15)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    center_height := terrain.sample_height(&editor.project, 0, MARKOV_FARMLAND_ORIGIN_X, MARKOV_FARMLAND_ORIGIN_Z)
    if target == "high" {
        editor.camera_pose = third_person.camera_look_at(
            {MARKOV_FARMLAND_ORIGIN_X + 42, center_height + 190, MARKOV_FARMLAND_ORIGIN_Z + 54},
            {MARKOV_FARMLAND_ORIGIN_X, center_height, MARKOV_FARMLAND_ORIGIN_Z},
        )
    } else {
        editor.camera_pose = third_person.camera_look_at(
            {MARKOV_FARMLAND_ORIGIN_X + 72, center_height + 48, MARKOV_FARMLAND_ORIGIN_Z + 82},
            {MARKOV_FARMLAND_ORIGIN_X, center_height, MARKOV_FARMLAND_ORIGIN_Z},
        )
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

markov_farmland_process_input :: proc(_: ^Editor) {  }

markov_farmland_draw_ui :: proc(_: ^Editor, _: i32, _: i32) {  }
