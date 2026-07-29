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

Farmland_Lab_Terrain :: enum u8 {
    Flat,
    Incline,
    Terrace,
    Cliff,
}

Farm_Instance :: struct {
    plan:     farmland.Plan,
    origin_x: f32,
    origin_z: f32,
    yaw:      f32,
    scale_x:  f32,
    scale_z:  f32,
}

markov_farmland_plan: farmland.Plan
farmland_render_origin_x := MARKOV_FARMLAND_ORIGIN_X
farmland_render_origin_z := MARKOV_FARMLAND_ORIGIN_Z
farmland_render_yaw := f32(-.14)
farmland_render_scale_x := f32(1)
farmland_render_scale_z := f32(1)
farmland_render_preview := false
farmland_render_width := farmland.GRID_WIDTH
farmland_render_height := farmland.GRID_HEIGHT
farmland_render_tradition := farmland.Tradition.Ancient_Enclosure
markov_farmland_lab_terrain := Farmland_Lab_Terrain.Flat
markov_farmland_lab_input_ready := false

farmland_warp_grid :: proc(grid_x, grid_z: f32) -> (f32, f32) {
    if farmland_render_tradition == .Parliamentary_Enclosure {
        // Surveyed enclosure boundaries read as deliberately straight, with
        // only a trace of terrain settlement to avoid synthetic perfection.
        warp_x := math.sin(grid_z * .17 - grid_x * .05) * .07
        warp_z := math.sin(grid_x * .15 + grid_z * .04) * .06
        return grid_x + warp_x, grid_z + warp_z
    }
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

farmland_world_xz :: proc(grid_x, grid_z: f32) -> (f32, f32) {
    warped_x, warped_z := farmland_warp_grid(grid_x, grid_z)
    local_x := (warped_x - f32(farmland_render_width) * .5) * farmland.CELL_METERS * farmland_render_scale_x
    local_z := (warped_z - f32(farmland_render_height) * .5) * farmland.CELL_METERS * farmland_render_scale_z
    // A slight landscape-scale yaw prevents the farm envelope from aligning
    // with the world axes even where the boundary displacement crosses zero.
    cosine, sine := math.cos(farmland_render_yaw), math.sin(farmland_render_yaw)
    x := farmland_render_origin_x + local_x * cosine - local_z * sine
    z := farmland_render_origin_z + local_x * sine + local_z * cosine
    return x, z
}

farmland_world_point :: proc(editor: ^Editor, grid_x, grid_z: f32, lift: f32) -> third_person.Vec3 {
    x, z := farmland_world_xz(grid_x, grid_z)
    y := terrain.sample_height(&editor.project, 0, x, z) + lift
    return {x, y, z}
}

farmland_surface_is_safe :: proc(editor: ^Editor, grid_x, grid_z: f32) -> bool {
    if editor == nil do return false
    if !lab_scene_is_active(editor, "markov-farmland") do return true
    x, z := farmland_world_xz(grid_x, grid_z)
    local_x := x - MARKOV_FARMLAND_ORIGIN_X
    local_z := z - MARKOV_FARMLAND_ORIGIN_Z
    switch markov_farmland_lab_terrain {
    case .Flat:
        return true
    case .Incline:
        return true
    case .Terrace:
        terrace_coordinate := local_z + local_x * .12
        return abs(terrace_coordinate + 34) > 4.5 && abs(terrace_coordinate - 34) > 4.5
    case .Cliff:
        cliff_coordinate := local_x - local_z * .10 - 24
        // The escarpment is a hard holding boundary: keep the upper bench and
        // reject both the face and the disconnected lower ground beyond it.
        return cliff_coordinate < -5
    }
    return true
}

farmland_raw_patch :: proc(editor: ^Editor, x0, z0, x1, z1: f32, color: rl.Color, lift: f32 = .16) {
    a := farmland_world_point(editor, x0, z0, lift)
    b := farmland_world_point(editor, x0, z1, lift)
    c := farmland_world_point(editor, x1, z1, lift)
    d := farmland_world_point(editor, x1, z0, lift)
    world_quad(a, b, c, d, color)
}

farmland_patch :: proc(editor: ^Editor, x0, z0, x1, z1: f32, color: rl.Color, lift: f32 = .16) {
    if !farmland_surface_is_safe(editor, x0, z0) ||
       !farmland_surface_is_safe(editor, x0, z1) ||
       !farmland_surface_is_safe(editor, x1, z0) ||
       !farmland_surface_is_safe(editor, x1, z1) {
        return
    }
    farmland_raw_patch(editor, x0, z0, x1, z1, color, lift)
}

farmland_hedgerow :: proc(editor: ^Editor, x0, z0, x1, z1: f32, seed: u32, detail_fade: f32) {
    if detail_fade <= .18 || farmland_render_preview do return
    grid_dx, grid_dz := x1 - x0, z1 - z0
    grid_length := f32(math.sqrt(f64(grid_dx * grid_dx + grid_dz * grid_dz)))
    segment_count := max(int(math.ceil(f64(grid_length * farmland.CELL_METERS / 12))), 1)
    for segment in 0 ..< segment_count {
        t0 := f32(segment) / f32(segment_count)
        t1 := f32(segment + 1) / f32(segment_count)
        midpoint_t := (t0 + t1) * .5
        if !farmland_surface_is_safe(editor, x0 + grid_dx * t0, z0 + grid_dz * t0) ||
           !farmland_surface_is_safe(editor, x0 + grid_dx * midpoint_t, z0 + grid_dz * midpoint_t) ||
           !farmland_surface_is_safe(editor, x0 + grid_dx * t1, z0 + grid_dz * t1) {
            continue
        }
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

farmland_render_crops :: proc(
    editor: ^Editor,
    parcel: farmland.Parcel,
    parcel_index: int,
    plan_seed: u32,
    detail_fade: f32,
) {
    if editor == nil || farmland_render_preview || detail_fade <= .12 || parcel.crop == .Fallow do return
    subdivisions := 2
    if parcel.crop == .Wheat do subdivisions = 3
    for z in parcel.min_z ..< parcel.max_z {
        for x in parcel.min_x ..< parcel.max_x {
            for sub_z in 0 ..< subdivisions {
                for sub_x in 0 ..< subdivisions {
                    sample_index :=
                        (parcel_index + 1) * 104729 +
                        x * 73856093 +
                        z * 19349663 +
                        sub_x * 83492791 +
                        sub_z * 265443576
                    mixed := farmland.mix(plan_seed ~ u32(sample_index))
                    jitter_x := (f32(mixed & 255) / 255 - .5) * .18
                    jitter_z := (f32((mixed >> 8) & 255) / 255 - .5) * .18
                    grid_x := f32(x) + (f32(sub_x) + .5) / f32(subdivisions) + jitter_x
                    grid_z := f32(z) + (f32(sub_z) + .5) / f32(subdivisions) + jitter_z
                    if !farmland_surface_is_safe(editor, grid_x, grid_z) do continue
                    point := farmland_world_point(editor, grid_x, grid_z, .03)
                    height, width := f32(.35), f32(.24)
                    color := farmland_color(parcel.crop, parcel.tint)
                    switch parcel.crop {
                    case .Wheat:
                        height = .72 + f32((mixed >> 16) & 255) / 255 * .42
                        width = .30 + height * .18
                        color = color_lerp(color, {226, 193, 91, 255}, .36)
                    case .Clover:
                        height = .18 + f32((mixed >> 16) & 255) / 255 * .18
                        width = .30 + f32((mixed >> 24) & 255) / 255 * .20
                        color = color_lerp(color, {75, 151, 67, 255}, .34)
                    case .Vineyard:
                        // Skip alternating sub-rows to leave visible cultivated
                        // alleys between the vines.
                        if sub_z & 1 != 0 do continue
                        height = .82 + f32((mixed >> 16) & 255) / 255 * .40
                        width = .52 + f32((mixed >> 24) & 255) / 255 * .24
                        color = color_lerp(color, {62, 104, 48, 255}, .28)
                    case .Olive:
                        // Olive groves are open-spaced rather than carpeted.
                        if x % 3 != 1 || z % 3 != 1 || sub_x != 0 || sub_z != 0 do continue
                        height = 2.15 + f32((mixed >> 16) & 255) / 255 * .55
                        width = 1.65 + f32((mixed >> 24) & 255) / 255 * .55
                        color = color_lerp(color, {104, 123, 79, 255}, .48)
                    case .Fallow:
                        continue
                    }
                    color.a = u8(clamp(detail_fade * 255, 0, 255))
                    world_grass_card({point.x, point.y + height * .5, point.z}, width, height, int(mixed % 16), color)
                }
            }
        }
    }
}

farmland_instance_contains_world_point :: proc(farm: ^Farm_Instance, x, z: f32, margin: f32 = 0) -> bool {
    if farm == nil || !farm.plan.valid do return false
    scale_x := farm.scale_x > 0 ? farm.scale_x : f32(1)
    scale_z := farm.scale_z > 0 ? farm.scale_z : f32(1)
    dx, dz := x - farm.origin_x, z - farm.origin_z
    cosine, sine := math.cos(farm.yaw), math.sin(farm.yaw)
    local_x := dx * cosine + dz * sine
    local_z := -dx * sine + dz * cosine
    half_width := f32(farm.plan.width) * farmland.CELL_METERS * scale_x * .5 + margin
    half_height := f32(farm.plan.height) * farmland.CELL_METERS * scale_z * .5 + margin
    return abs(local_x) <= half_width && abs(local_z) <= half_height
}

farmland_excludes_ground_grass :: proc(editor: ^Editor, x, z: f32) -> bool {
    if editor == nil do return false
    for &farm in editor.farms[:editor.farm_count] {
        if farmland_instance_contains_world_point(&farm, x, z, .8) do return true
    }
    if editor.farm_paint_mode &&
       editor.farm_preview_valid &&
       farmland_instance_contains_world_point(&editor.farm_preview, x, z, .8) {
        return true
    }
    return false
}

farmland_render_plan :: proc(editor: ^Editor, plan: ^farmland.Plan) {
    if editor == nil || plan == nil || !plan.valid do return
    farmland_render_width = plan.width
    farmland_render_height = plan.height
    farmland_render_tradition = plan.tradition
    center_height := terrain.sample_height(&editor.project, 0, farmland_render_origin_x, farmland_render_origin_z)
    altitude := max(editor.camera_pose.position.y - center_height, f32(0))
    detail_fade := 1 - clamp((altitude - 42) / 115, f32(0), f32(1))
    // Keep the inexpensive 5 m terrain mesh at every altitude. Coarsening to
    // 20 m saved only a few hundred quads, but bridged over hill curvature and
    // let the ground punch through. Detail still halves aloft via row collapse.
    step := 1
    verge := f32(.10)
    row_subdivisions := detail_fade > .62 ? 2 : 1

    for parcel, parcel_index in plan.parcels[:plan.parcel_count] {
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
        farmland_render_crops(editor, parcel, parcel_index, plan.seed, detail_fade)

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
        if plan.tradition == .Parliamentary_Enclosure || farmland.mix(hedge_seed) & 3 != 0 {
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
        if plan.tradition == .Parliamentary_Enclosure || farmland.mix(hedge_seed ~ u32(0xc2b2ae35)) & 3 != 0 {
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
        if parcel.max_x == plan.width {
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
        if parcel.max_z == plan.height {
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

    // Only larger field systems need an internal access spine. On compact
    // one- and two-field holdings it read as another arbitrary subdivision.
    if plan.parcel_count >= 3 {
        track := color_lerp(rl.Color{151, 119, 75, 255}, rl.Color{176, 151, 101, 255}, 1 - detail_fade)
        track_half_width := f32(.16)
        track_x := f32(plan.width / 2)
        track_z := f32(plan.height / 2)
        for z := 0; z < plan.height; z += 5 {
            farmland_patch(
                editor,
                track_x - track_half_width,
                f32(z),
                track_x + track_half_width,
                f32(min(z + 5, plan.height)),
                track,
                .19,
            )
        }
        for x := 0; x < plan.width / 2; x += 5 {
            farmland_patch(
                editor,
                f32(x),
                track_z - track_half_width,
                f32(min(x + 5, plan.width / 2)),
                track_z + track_half_width,
                track,
                .19,
            )
        }
    }
}

world_markov_farmland :: proc(editor: ^Editor) {
    farmland_render_origin_x = MARKOV_FARMLAND_ORIGIN_X
    farmland_render_origin_z = MARKOV_FARMLAND_ORIGIN_Z
    farmland_render_yaw = -.14
    farmland_render_scale_x = 1
    farmland_render_scale_z = 1
    farmland_render_preview = false
    farmland_render_plan(editor, &markov_farmland_plan)
    markov_farmland_lab_terrace_walls(editor)
}

world_authored_farmland :: proc(editor: ^Editor) {
    if editor == nil do return
    for &instance in editor.farms[:editor.farm_count] {
        farmland_render_origin_x = instance.origin_x
        farmland_render_origin_z = instance.origin_z
        farmland_render_yaw = instance.yaw
        farmland_render_scale_x = instance.scale_x > 0 ? instance.scale_x : f32(1)
        farmland_render_scale_z = instance.scale_z > 0 ? instance.scale_z : f32(1)
        farmland_render_preview = false
        farmland_render_plan(editor, &instance.plan)
    }
    if editor.farm_paint_mode && editor.farm_preview_valid {
        farmland_render_origin_x = editor.farm_preview.origin_x
        farmland_render_origin_z = editor.farm_preview.origin_z
        farmland_render_yaw = editor.farm_preview.yaw
        farmland_render_scale_x = editor.farm_preview.scale_x > 0 ? editor.farm_preview.scale_x : f32(1)
        farmland_render_scale_z = editor.farm_preview.scale_z > 0 ? editor.farm_preview.scale_z : f32(1)
        farmland_render_preview = true
        farmland_render_plan(editor, &editor.farm_preview.plan)
        farmland_render_preview = false
    }
}

settlement_village_attach_farmland :: proc(editor: ^Editor) -> bool {
    if editor == nil ||
       editor.settlement_plan.request.scale != .Village ||
       editor.settlement_plan.village_reason != .Agricultural_Terrace ||
       editor.farm_count >= FARM_INSTANCE_CAPACITY {
        return false
    }
    common := editor.settlement_plan.request.center
    if editor.settlement_plan.neighborhood_count > 0 {
        common = editor.settlement_plan.neighborhoods[0].center
    }
    farmstead_index := -1
    farmstead_distance_squared := f32(-1)
    for site, site_index in editor.settlement_plan.sites[:editor.settlement_plan.site_count] {
        if !site.accepted || site.kind != .Ordinary || site.purpose != .Farmstead do continue
        dx, dz := site.structure.center_x - common[0], site.structure.center_z - common[1]
        distance_squared := dx * dx + dz * dz
        if distance_squared > farmstead_distance_squared {
            farmstead_index = site_index
            farmstead_distance_squared = distance_squared
        }
    }
    if farmstead_index < 0 do return false

    farmstead := editor.settlement_plan.sites[farmstead_index].structure
    outward_x, outward_z := farmstead.center_x - common[0], farmstead.center_z - common[1]
    outward_length := f32(math.sqrt(f64(outward_x * outward_x + outward_z * outward_z)))
    if outward_length < .01 {
        outward_x, outward_z = f32(math.cos(f64(farmstead.rotation))), f32(math.sin(f64(farmstead.rotation)))
    } else {
        outward_x /= outward_length
        outward_z /= outward_length
    }
    grid_width := editor.settlement_plan.request.region == .Aegean ? 8 : 10
    grid_height := editor.settlement_plan.request.region == .Aegean ? 8 : 9
    field_offset := f32(grid_width) * farmland.CELL_METERS * .5 + farmstead.depth * .5 + 3
    seed := editor.settlement_plan.request.seed ~ farmstead.seed ~ u32(0x4641524d)
    plan := farmland.generate_sized(seed, grid_width, grid_height, context.temp_allocator)
    if !farmland.validate(&plan) do return false
    editor.farms[editor.farm_count] = {
        plan     = plan,
        origin_x = farmstead.center_x + outward_x * field_offset,
        origin_z = farmstead.center_z + outward_z * field_offset,
        yaw      = farmstead.rotation,
        scale_x  = 1,
        scale_z  = 1,
    }
    editor.farm_count += 1
    return true
}

markov_farmland_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    markov_farmland_lab_terrain = .Flat
    markov_farmland_lab_input_ready = false
    seed := MARKOV_FARMLAND_DEFAULT_SEED
    if parsed, ok := strconv.parse_int(target); ok && parsed >= 0 && parsed <= 0xffffffff {
        seed = u32(parsed)
    }
    grid_width, grid_height := farmland.GRID_WIDTH, farmland.GRID_HEIGHT
    switch target {
    case "small":
        grid_width, grid_height = 8, 8
    case "medium":
        grid_width, grid_height = farmland.GRID_WIDTH, farmland.GRID_HEIGHT
    case "large":
        grid_width, grid_height = 48, 36
    case "flat":
        markov_farmland_lab_terrain = .Flat
    case "incline":
        markov_farmland_lab_terrain = .Incline
    case "terrace":
        markov_farmland_lab_terrain = .Terrace
    case "cliff":
        markov_farmland_lab_terrain = .Cliff
    }
    markov_farmland_plan = farmland.generate_sized(seed, grid_width, grid_height, context.temp_allocator)
    if !farmland.validate(&markov_farmland_plan) do return false
    markov_farmland_lab_apply_terrain(editor, markov_farmland_lab_terrain)

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
        third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
        third_person.camera_set_active(&editor.cameras, .Inspection)
    } else {
        markov_farmland_lab_configure_camera(editor)
    }
    return true
}

markov_farmland_lab_height :: proc(kind: Farmland_Lab_Terrain, x, z: f32) -> f32 {
    local_x := x - MARKOV_FARMLAND_ORIGIN_X
    local_z := z - MARKOV_FARMLAND_ORIGIN_Z
    switch kind {
    case .Flat:
        return 10
    case .Incline:
        // A continuous diagonal grade exercises terrain conformity without
        // terrace transitions or exclusion gaps obscuring the result. Clamp
        // only beyond the lab's inspection area so the distant terrain stays
        // above sea level instead of turning the horizon into a shoreline.
        ramp_x := clamp(local_x, f32(-160), f32(160))
        ramp_z := clamp(local_z, f32(-160), f32(160))
        return 22 + ramp_x * .075 + ramp_z * .035
    case .Terrace:
        // Three broad agricultural benches with eased stone-bank transitions.
        terrace_coordinate := local_z + local_x * .12
        height := f32(7)
        lower_fraction := clamp((terrace_coordinate + 37) / 6, 0, 1)
        lower_eased := lower_fraction * lower_fraction * (3 - 2 * lower_fraction)
        upper_fraction := clamp((terrace_coordinate - 31) / 6, 0, 1)
        upper_eased := upper_fraction * upper_fraction * (3 - 2 * upper_fraction)
        height += (lower_eased + upper_eased) * 5
        return height
    case .Cliff:
        // The nominal farm envelope crosses this escarpment. The renderer's
        // suitability mask must leave the abrupt face free of fields and
        // hedges while retaining cultivable ground on both benches.
        cliff_coordinate := local_x - local_z * .10 - 24
        fraction := clamp((cliff_coordinate + 2) / 4, 0, 1)
        eased := fraction * fraction * (3 - 2 * fraction)
        return 28 - eased * 18
    }
    return 10
}

markov_farmland_lab_point_in_farm :: proc(x, z: f32, verge: f32 = 0) -> bool {
    local_x := x - MARKOV_FARMLAND_ORIGIN_X
    local_z := z - MARKOV_FARMLAND_ORIGIN_Z
    cosine, sine := math.cos(f32(-.14)), math.sin(f32(-.14))
    farm_local_x := local_x * cosine + local_z * sine
    farm_local_z := -local_x * sine + local_z * cosine
    farm_half_width := f32(markov_farmland_plan.width) * farmland.CELL_METERS * .5 + verge
    farm_half_height := f32(markov_farmland_plan.height) * farmland.CELL_METERS * .5 + verge
    return abs(farm_local_x) <= farm_half_width && abs(farm_local_z) <= farm_half_height
}

markov_farmland_lab_terrace_walls :: proc(editor: ^Editor) {
    if editor == nil || !lab_scene_is_active(editor, "markov-farmland") || markov_farmland_lab_terrain != .Terrace {
        return
    }

    // Dry-stacked limestone walls hold the two terrace cuts. The terrain
    // remains naturally grassed, while cultivated surfaces stop at a narrow
    // verge above and below each wall.
    normal_length := f32(math.sqrt(f64(1 + .12 * .12)))
    normal_x, normal_z := .12 / normal_length, 1 / normal_length
    direction_x, direction_z := 1 / normal_length, -.12 / normal_length
    yaw := math.atan2(direction_z, direction_x)
    SEGMENT_LENGTH :: f32(4)
    half_extent := f32(max(markov_farmland_plan.width, markov_farmland_plan.height)) * farmland.CELL_METERS * .75
    for edge_index in 0 ..< 2 {
        edge := edge_index == 0 ? f32(-34) : f32(34)
        closest_scale := edge / (1 + .12 * .12)
        closest_x := normal_x * closest_scale * normal_length
        closest_z := normal_z * closest_scale * normal_length
        segment_count := int(math.ceil(f64(half_extent * 2 / SEGMENT_LENGTH)))
        for segment in 0 ..< segment_count {
            along := -half_extent + (f32(segment) + .5) * SEGMENT_LENGTH
            x := MARKOV_FARMLAND_ORIGIN_X + closest_x + direction_x * along
            z := MARKOV_FARMLAND_ORIGIN_Z + closest_z + direction_z * along
            if !markov_farmland_lab_point_in_farm(x, z, 1) do continue
            lower_x, lower_z := x - normal_x * 4, z - normal_z * 4
            upper_x, upper_z := x + normal_x * 4, z + normal_z * 4
            lower_y := terrain.sample_height(&editor.project, 0, lower_x, lower_z)
            upper_y := terrain.sample_height(&editor.project, 0, upper_x, upper_z)
            wall_height := max(upper_y - lower_y, f32(.8))
            base_stone := edge_index == 0 ? rl.Color{119, 116, 103, 255} : rl.Color{131, 126, 108, 255}
            COURSE_COUNT :: 4
            course_height := wall_height / COURSE_COUNT
            for course in 0 ..< COURSE_COUNT {
                for block in 0 ..< 2 {
                    stagger := course & 1 == 0 ? f32(0) : f32(.22)
                    block_along := (f32(block) - .5) * SEGMENT_LENGTH * .5 + stagger
                    block_x := x + direction_x * block_along
                    block_z := z + direction_z * block_along
                    shade := f32((segment * 3 + course * 2 + block + edge_index) % 5) / 4
                    stone := color_lerp(base_stone, {158, 148, 123, 255}, shade * .32)
                    world_box_rotated(
                        {block_x, lower_y + (f32(course) + .5) * course_height, block_z},
                        {SEGMENT_LENGTH * .51, max(course_height - .055, f32(.12)), .78},
                        yaw,
                        stone,
                    )
                }
            }
            coping := color_lerp(base_stone, {188, 178, 148, 255}, .34)
            world_box_rotated({x, lower_y + wall_height + .07, z}, {SEGMENT_LENGTH + .12, .18, .92}, yaw, coping)
        }
    }
}

markov_farmland_lab_apply_terrain :: proc(editor: ^Editor, kind: Farmland_Lab_Terrain) {
    if editor == nil do return
    markov_farmland_lab_terrain = kind
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        data := &editor.project.levels[level]
        for z in 0 ..< terrain.TERRAIN_RESOLUTION {
            world_z := data.origin_z + f32(z) * data.cell_size
            for x in 0 ..< terrain.TERRAIN_RESOLUTION {
                world_x := data.origin_x + f32(x) * data.cell_size
                index := terrain.sample_index(x, z)
                data.heights[index] = markov_farmland_lab_height(kind, world_x, world_z)
                data.material[index] = .18
            }
        }
    }
    editor.project.revision += 1
    world_terrain_invalidate_all(editor)
}

markov_farmland_lab_terrain_name :: proc(kind: Farmland_Lab_Terrain) -> cstring {
    switch kind {
    case .Flat:
        return "FLAT FARM"
    case .Incline:
        return "PLAIN INCLINE"
    case .Terrace:
        return "TERRACES"
    case .Cliff:
        return "CLIFF EXCLUSION"
    }
    return "FARM"
}

markov_farmland_lab_configure_camera :: proc(editor: ^Editor) {
    if editor == nil do return
    extent := f32(max(markov_farmland_plan.width, markov_farmland_plan.height)) * farmland.CELL_METERS
    center_height := terrain.sample_height(&editor.project, 0, MARKOV_FARMLAND_ORIGIN_X, MARKOV_FARMLAND_ORIGIN_Z)
    eye := third_person.Vec3 {
        MARKOV_FARMLAND_ORIGIN_X + extent * .58,
        center_height + extent * .40,
        MARKOV_FARMLAND_ORIGIN_Z + extent * .66,
    }
    focus := third_person.Vec3{MARKOV_FARMLAND_ORIGIN_X, center_height, MARKOV_FARMLAND_ORIGIN_Z}
    switch markov_farmland_lab_terrain {
    case .Incline:
        // Look across the diagonal grade at a low enough angle that the
        // continuous rise is visible behind the field rows.
        eye = {
            MARKOV_FARMLAND_ORIGIN_X + extent * .72,
            center_height + extent * .24,
            MARKOV_FARMLAND_ORIGIN_Z - extent * .68,
        }
        focus.y += 2
    case .Terrace:
        // Face uphill across both risers so the three cultivable benches and
        // their deliberate exclusion gaps can be judged in one frame.
        eye = {
            MARKOV_FARMLAND_ORIGIN_X + extent * .10,
            center_height + extent * .22,
            MARKOV_FARMLAND_ORIGIN_Z - extent * .82,
        }
        focus.y += 3
    case .Flat, .Cliff:
    }
    editor.camera_pose = third_person.camera_look_at(eye, focus)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

markov_farmland_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    if !markov_farmland_lab_input_ready {
        // Ignore launch-frame key transitions so command-line presets remain
        // deterministic when the new SDL window acquires keyboard focus.
        markov_farmland_lab_input_ready = true
        return
    }
    selected := markov_farmland_lab_terrain
    if rl.IsKeyPressed(.ONE) do selected = .Flat
    if rl.IsKeyPressed(.TWO) do selected = .Terrace
    if rl.IsKeyPressed(.THREE) do selected = .Cliff
    if rl.IsKeyPressed(.FOUR) do selected = .Incline
    if selected != markov_farmland_lab_terrain {
        markov_farmland_lab_apply_terrain(editor, selected)
        markov_farmland_lab_configure_camera(editor)
    }
}

markov_farmland_draw_ui :: proc(_: ^Editor, _: i32, _: i32) {
    panel := rl.Rectangle {
        x      = 22,
        y      = 22,
        width  = 430,
        height = 112,
    }
    rl.DrawRectangleRounded(panel, .12, 8, {10, 27, 37, 226})
    rl.DrawRectangleRoundedLinesEx(panel, .12, 8, 1, {104, 168, 184, 255})
    rl.DrawTextEx(rl.Font{}, "MARKOV FARMLAND", {38, 38}, 20, 1, {245, 238, 197, 255})
    rl.DrawTextEx(
        rl.Font{},
        markov_farmland_lab_terrain_name(markov_farmland_lab_terrain),
        {38, 68},
        17,
        1,
        {105, 215, 198, 255},
    )
    rl.DrawTextEx(rl.Font{}, "1 FLAT   2 TERRACE   3 CLIFF   4 INCLINE", {38, 98}, 14, 1, {190, 207, 211, 255})
}
