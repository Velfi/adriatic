package plant_assets

import branch_mesh "../branch_mesh"
import leaf_mesh "../leaf_mesh"
import plant_structure "../plant_structure"
import plants "../plants"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"

PLANT_ASSET_MAGIC :: u64(0x544e414c50524441) // "ADRPLANT" little-endian
PLANT_ASSET_FORMAT_VERSION :: u32(7)
PLANT_GENERATOR_VERSION :: u32(6)
PLANT_ASSET_LOD_COUNT :: 5
PLANT_IMPOSTOR_AZIMUTH_COUNT :: 8
PLANT_IMPOSTOR_ELEVATION_COUNT :: 3
PLANT_IMPOSTOR_VIEW_COUNT :: PLANT_IMPOSTOR_AZIMUTH_COUNT * PLANT_IMPOSTOR_ELEVATION_COUNT
PLANT_IMPOSTOR_TILE_SIZE :: 64
PLANT_IMPOSTOR_ATLAS_WIDTH :: PLANT_IMPOSTOR_TILE_SIZE * PLANT_IMPOSTOR_AZIMUTH_COUNT
PLANT_IMPOSTOR_ATLAS_HEIGHT :: PLANT_IMPOSTOR_TILE_SIZE * PLANT_IMPOSTOR_ELEVATION_COUNT
PLANT_MATURITY_STEPS :: 5

Plant_Asset_Request :: struct {
    species:       plants.Species,
    seed:          u64,
    maturity_step: u8,
    habit:         plants.Growth_Habit,
    site:          plants.Site_Context,
}

Plant_Asset_LOD_Header :: struct {
    segment_count:  u32,
    vertex_count:   u32,
    index_count:    u32,
    organ_count:    u32,
    segment_offset: u64,
    vertex_offset:  u64,
    index_offset:   u64,
    organ_offset:   u64,
}

Plant_Asset_Header :: struct {
    magic:                  u64,
    format_version:         u32,
    generator_version:      u32,
    source_key:             u64,
    request:                Plant_Asset_Request,
    bounds_min:             [3]f32,
    bounds_max:             [3]f32,
    radial_irregularity:    f32,
    bark_twist:             f32,
    wind_compliance:        f32,
    root_kind:              plants.Root_Kind,
    support_signature:      u64,
    bark_material_ref:      u32,
    organ_material_ref:     u32,
    collision_radius:       f32,
    collision_height:       f32,
    lods:                   [PLANT_ASSET_LOD_COUNT]Plant_Asset_LOD_Header,
    impostor_azimuths:      u8,
    impostor_elevations:    u8,
    impostor_pivot:         [3]f32,
    impostor_views:         [PLANT_IMPOSTOR_VIEW_COUNT]Plant_Impostor_View,
    impostor_width:         u16,
    impostor_height:        u16,
    impostor_color_offset:  u64,
    impostor_color_size:    u64,
    impostor_normal_offset: u64,
    impostor_normal_size:   u64,
    payload_checksum:       u64,
}

Plant_Impostor_View :: struct {
    azimuth:    f32,
    elevation:  f32,
    uv_min:     [2]f32,
    uv_max:     [2]f32,
    bounds_min: [3]f32,
    bounds_max: [3]f32,
    pivot:      [3]f32,
}

Plant_Impostor_Selection :: struct {
    first:  int,
    second: int,
    blend:  f32,
}

Plant_Asset_Segment :: struct {
    start:            [3]f32,
    end:              [3]f32,
    radius_start:     f32,
    radius_end:       f32,
    depth:            i32,
    parent:           i32,
    axis:             i32,
    stable_id:        u64,
    axis_parent:      i32,
    axis_role:        plants.Axis_Role,
    axis_orientation: plants.Axis_Orientation,
    axis_stable_id:   u64,
    growth_stable_id: u64,
    bud_stable_id:    u64,
    bud_state:        plants.Bud_State,
}

Plant_Asset_Vertex :: struct {
    position:         [3]f32,
    normal:           [3]f32,
    uv:               [2]f32,
    primary_anchor:   [3]f32,
    secondary_anchor: [3]f32,
    axis_position:    f32,
    stiffness:        f32,
    leaf_pivot:       [3]f32,
    flutter:          f32,
    hierarchy_depth:  u8,
    phase:            f32,
}

Plant_Asset_Organ :: struct {
    position:          [3]f32,
    forward:           [3]f32,
    up:                [3]f32,
    stable_id:         u64,
    kind:              plants.Attachment_Kind,
    stage:             plants.Attachment_Stage,
    depth:             i32,
    variant:           u8,
    leaf_shape:        u8,
    leaf_length:       f32,
    leaf_width:        f32,
    leaf_serration:    f32,
    leaf_curl:         f32,
    leaf_cup:          f32,
    leaf_thickness:    f32,
    architecture_kind: plants.Architecture_Organ,
}

Plant_Asset_LOD :: struct {
    segments: [dynamic]Plant_Asset_Segment,
    vertices: [dynamic]Plant_Asset_Vertex,
    indices:  [dynamic]u32,
    organs:   [dynamic]Plant_Asset_Organ,
}

Plant_Asset :: struct {
    header:          Plant_Asset_Header,
    lods:            [PLANT_ASSET_LOD_COUNT]Plant_Asset_LOD,
    impostor_color:  [dynamic]byte,
    impostor_normal: [dynamic]byte,
}

Plant_Asset_Mesh :: struct {
    vertices:        [dynamic]Plant_Asset_Vertex,
    indices:         [dynamic]u32,
    impostor_color:  [dynamic]byte,
    impostor_normal: [dynamic]byte,
    impostor_views:  [PLANT_IMPOSTOR_VIEW_COUNT]Plant_Impostor_View,
    impostor_width:  int,
    impostor_height: int,
}

plant_asset_mesh_destroy :: proc(mesh: ^Plant_Asset_Mesh) {
    if mesh == nil do return
    delete(mesh.vertices)
    delete(mesh.indices)
    delete(mesh.impostor_color)
    delete(mesh.impostor_normal)
    mesh^ = {}
}

plant_asset_destroy :: proc(asset: ^Plant_Asset) {
    if asset == nil do return
    for &lod in asset.lods {
        delete(lod.segments)
        delete(lod.vertices)
        delete(lod.indices)
        delete(lod.organs)
    }
    delete(asset.impostor_color)
    delete(asset.impostor_normal)
    asset^ = {}
}

plant_asset_hash_u64 :: #force_inline proc(hash, value: u64) -> u64 {
    result := hash
    for shift := u64(0); shift < 64; shift += 8 {
        result = (result ~ ((value >> shift) & 0xff)) * 1099511628211
    }
    return result
}

plant_asset_source_key :: proc(request: Plant_Asset_Request) -> u64 {
    hash := u64(1469598103934665603)
    hash = plant_asset_hash_u64(hash, u64(PLANT_GENERATOR_VERSION))
    hash = plant_asset_hash_u64(hash, u64(request.species))
    hash = plant_asset_hash_u64(hash, request.seed)
    hash = plant_asset_hash_u64(hash, u64(request.maturity_step))
    hash = plant_asset_hash_u64(hash, u64(request.habit))
    return plant_asset_hash_u64(hash, plants.site_context_signature(request.site))
}

plant_asset_detail :: #force_inline proc(lod: int) -> plants.Detail_Level {
    if lod <= 1 do return .Near
    if lod == 2 do return .Medium
    return .Far
}

plant_impostor_stamp :: proc(color, normal: []byte, center_x, center_y, radius: f32, rgba, encoded_normal: [4]byte) {
    minimum_x := clamp(int(math.floor(center_x - radius)), 0, PLANT_IMPOSTOR_ATLAS_WIDTH - 1)
    maximum_x := clamp(int(math.ceil(center_x + radius)), 0, PLANT_IMPOSTOR_ATLAS_WIDTH - 1)
    minimum_y := clamp(int(math.floor(center_y - radius)), 0, PLANT_IMPOSTOR_ATLAS_HEIGHT - 1)
    maximum_y := clamp(int(math.ceil(center_y + radius)), 0, PLANT_IMPOSTOR_ATLAS_HEIGHT - 1)
    radius_squared := radius * radius
    for y in minimum_y ..= maximum_y {
        for x in minimum_x ..= maximum_x {
            dx, dy := f32(x) + .5 - center_x, f32(y) + .5 - center_y
            if dx * dx + dy * dy > radius_squared do continue
            offset := (y * PLANT_IMPOSTOR_ATLAS_WIDTH + x) * 4
            if color[offset + 3] > rgba[3] do continue
            color[offset + 0] = rgba[0]
            color[offset + 1] = rgba[1]
            color[offset + 2] = rgba[2]
            color[offset + 3] = rgba[3]
            normal[offset + 0] = encoded_normal[0]
            normal[offset + 1] = encoded_normal[1]
            normal[offset + 2] = encoded_normal[2]
            normal[offset + 3] = encoded_normal[3]
        }
    }
}

plant_asset_generate_impostors :: proc(asset: ^Plant_Asset) {
    if asset == nil do return
    pixel_count := PLANT_IMPOSTOR_ATLAS_WIDTH * PLANT_IMPOSTOR_ATLAS_HEIGHT
    asset.impostor_color = make([dynamic]byte, pixel_count * 4)
    asset.impostor_normal = make([dynamic]byte, pixel_count * 4)
    resize(&asset.impostor_color, pixel_count * 4)
    resize(&asset.impostor_normal, pixel_count * 4)
    pivot := asset.header.impostor_pivot
    extent_x := asset.header.bounds_max[0] - asset.header.bounds_min[0]
    extent_y := asset.header.bounds_max[1] - asset.header.bounds_min[1]
    extent_z := asset.header.bounds_max[2] - asset.header.bounds_min[2]
    projection_scale := f32(PLANT_IMPOSTOR_TILE_SIZE) * .82 / max(max(extent_x, extent_z), max(extent_y, f32(.01)))
    source := &asset.lods[3]
    for view in asset.header.impostor_views {
        tile_x :=
            int(math.round(f64(view.azimuth / math.TAU * PLANT_IMPOSTOR_AZIMUTH_COUNT))) % PLANT_IMPOSTOR_AZIMUTH_COUNT
        elevation_degrees := view.elevation * 180 / math.PI
        tile_y := elevation_degrees < 0 ? 0 : elevation_degrees < 30 ? 1 : 2
        right := plant_structure.Vec3{math.cos(view.azimuth), 0, -math.sin(view.azimuth)}
        up := plant_structure.Vec3 {
            -math.sin(view.azimuth) * math.sin(view.elevation),
            math.cos(view.elevation),
            -math.cos(view.azimuth) * math.sin(view.elevation),
        }
        project := proc(
            point: [3]f32,
            pivot: [3]f32,
            right, up: plant_structure.Vec3,
            tile_x, tile_y: int,
            scale, height: f32,
        ) -> (
            f32,
            f32,
        ) {
            relative := plant_structure.Vec3 {
                point[0] - pivot[0],
                point[1] - pivot[1] - height * .5,
                point[2] - pivot[2],
            }
            return f32(tile_x * PLANT_IMPOSTOR_TILE_SIZE) +
                PLANT_IMPOSTOR_TILE_SIZE * .5 +
                linalg.dot(relative, right) * scale,
                f32(tile_y * PLANT_IMPOSTOR_TILE_SIZE) +
                PLANT_IMPOSTOR_TILE_SIZE * .5 -
                linalg.dot(relative, up) * scale
        }
        for segment in source.segments {
            start_x, start_y := project(segment.start, pivot, right, up, tile_x, tile_y, projection_scale, extent_y)
            end_x, end_y := project(segment.end, pivot, right, up, tile_x, tile_y, projection_scale, extent_y)
            dx, dy := end_x - start_x, end_y - start_y
            steps := max(int(math.ceil(math.sqrt(dx * dx + dy * dy))), 1)
            for step in 0 ..= steps {
                t := f32(step) / f32(steps)
                radius := linalg.lerp(segment.radius_start, segment.radius_end, t) * projection_scale
                plant_impostor_stamp(
                    asset.impostor_color[:],
                    asset.impostor_normal[:],
                    start_x + dx * t,
                    start_y + dy * t,
                    max(radius, f32(.75)),
                    {104, 76, 48, 255},
                    {128, 196, 232, 255},
                )
            }
        }
        for organ in source.organs {
            x, y := project(organ.position, pivot, right, up, tile_x, tile_y, projection_scale, extent_y)
            radius := max(max(organ.leaf_width, organ.leaf_length * .24) * projection_scale, f32(1.1))
            color := [4]byte{73, 111, 57, 255}
            if organ.kind == .Flower do color = {214, 190, 174, 255}
            if organ.kind == .Fruit do color = {126, 65, 50, 255}
            plant_impostor_stamp(
                asset.impostor_color[:],
                asset.impostor_normal[:],
                x,
                y,
                radius,
                color,
                {128, 170, 242, 255},
            )
        }
    }
    asset.header.impostor_width = PLANT_IMPOSTOR_ATLAS_WIDTH
    asset.header.impostor_height = PLANT_IMPOSTOR_ATLAS_HEIGHT
}

plant_asset_compile :: proc(request: Plant_Asset_Request) -> (Plant_Asset, bool) {
    asset: Plant_Asset
    workspace: plants.Generation_Workspace
    if !plants.generation_workspace_begin(&workspace) do return {}, false
    defer {
        plants.generation_workspace_end(&workspace)
        plants.generation_workspace_destroy(&workspace)
    }
    asset.header.magic = PLANT_ASSET_MAGIC
    asset.header.format_version = PLANT_ASSET_FORMAT_VERSION
    asset.header.generator_version = PLANT_GENERATOR_VERSION
    asset.header.source_key = plant_asset_source_key(request)
    asset.header.request = request
    asset.header.bounds_min = {math.F32_MAX, math.F32_MAX, math.F32_MAX}
    asset.header.bounds_max = {-math.F32_MAX, -math.F32_MAX, -math.F32_MAX}
    asset.header.impostor_azimuths = PLANT_IMPOSTOR_AZIMUTH_COUNT
    asset.header.impostor_elevations = PLANT_IMPOSTOR_ELEVATION_COUNT

    maturity := f32(request.maturity_step) / PLANT_MATURITY_STEPS
    for lod_index in 0 ..< PLANT_ASSET_LOD_COUNT {
        result := plants.generate(
            {
                species = request.species,
                seed = request.seed,
                maturity = maturity,
                habit = request.habit,
                detail = plant_asset_detail(lod_index),
                site = request.site,
            },
        )
        if result.error != .None {
            plants.destroy(&result)
            plant_asset_destroy(&asset)
            return {}, false
        }
        if lod_index == 4 {
            // Distant is atlas-only. Keeping a redundant Far mesh here would
            // waste disk and upload memory and could accidentally restore
            // geometry at the final tier.
            plants.destroy(&result)
            continue
        }
        mesh := branch_mesh.generate(
            result.plant.segments[:],
            {
                radial_segments = lod_index == 0 ? 10 : lod_index == 1 ? 8 : lod_index == 2 ? 6 : 4,
                samples_per_segment = lod_index == 0 ? 4 : lod_index == 1 ? 3 : lod_index == 2 ? 2 : 1,
                minimum_radius = .0005,
                seed = request.seed,
                axis_ids = result.plant.segment_axes[:],
                parent_ids = result.plant.segment_parents[:],
            },
        )
        lod := &asset.lods[lod_index]
        for segment, segment_index in result.plant.segments {
            internode := result.plant.graph.internodes[segment_index]
            axis := result.plant.graph.axes[internode.axis]
            growth := result.plant.graph.growth_units[internode.growth_unit]
            bud_stable_id: u64
            bud_state := plants.Bud_State.Terminated
            for bud in result.plant.graph.buds {
                if bud.internode == segment_index {
                    bud_stable_id = bud.stable_id
                    bud_state = bud.state
                    break
                }
            }
            append(
                &lod.segments,
                Plant_Asset_Segment {
                    start = segment.start,
                    end = segment.end,
                    radius_start = segment.radius_start,
                    radius_end = segment.radius_end,
                    depth = i32(segment.depth),
                    parent = i32(result.plant.segment_parents[segment_index]),
                    axis = i32(result.plant.segment_axes[segment_index]),
                    stable_id = result.plant.segment_ids[segment_index],
                    axis_parent = i32(axis.parent_axis),
                    axis_role = axis.role,
                    axis_orientation = axis.orientation,
                    axis_stable_id = axis.stable_id,
                    growth_stable_id = growth.stable_id,
                    bud_stable_id = bud_stable_id,
                    bud_state = bud_state,
                },
            )
        }
        resize(&lod.vertices, len(mesh.vertices))
        for source, vertex_index in mesh.vertices {
            position := source.position
            nearest_segment := 0
            nearest_fraction := f32(0)
            nearest_distance := f32(math.F32_MAX)
            for segment, segment_index in result.plant.segments {
                direction := segment.end - segment.start
                length_squared := linalg.dot(direction, direction)
                fraction := f32(0)
                if length_squared > 1e-10 {
                    fraction = clamp(linalg.dot(position - segment.start, direction) / length_squared, f32(0), f32(1))
                }
                delta := position - (segment.start + direction * fraction)
                distance := linalg.dot(delta, delta)
                if distance < nearest_distance {
                    nearest_distance = distance
                    nearest_segment = segment_index
                    nearest_fraction = fraction
                }
            }
            axis := result.plant.segment_axes[nearest_segment]
            hierarchy_depth := 0
            primary_axis := axis
            for result.plant.axis_parents[primary_axis] >= 0 {
                primary_axis = result.plant.axis_parents[primary_axis]
                hierarchy_depth += 1
            }
            secondary_anchor := result.plant.segments[nearest_segment].start
            primary_anchor := secondary_anchor
            for candidate, candidate_index in result.plant.segments {
                candidate_axis := result.plant.segment_axes[candidate_index]
                if candidate_axis == axis && result.plant.segment_parents[candidate_index] < 0 ||
                   candidate_axis == axis &&
                       result.plant.segment_axes[result.plant.segment_parents[candidate_index]] != axis {
                    secondary_anchor = candidate.start
                }
                if candidate_axis == primary_axis && result.plant.segment_parents[candidate_index] < 0 {
                    primary_anchor = candidate.start
                }
            }
            segment := result.plant.segments[nearest_segment]
            axis_distance :=
                math.sqrt(linalg.dot(segment.end - segment.start, segment.end - segment.start)) * nearest_fraction
            lod.vertices[vertex_index] = {
                position         = position,
                normal           = source.normal,
                uv               = source.bark_uv,
                primary_anchor   = primary_anchor,
                secondary_anchor = secondary_anchor,
                axis_position    = axis_distance,
                stiffness        = 1 / (1 + f32(hierarchy_depth) * .42 + axis_distance * .18),
                hierarchy_depth  = u8(min(hierarchy_depth, 255)),
                phase            = f32(
                    (request.seed ~ u64(axis + 1) * 0x9e3779b97f4a7c15) & 0xffff,
                ) / 65535 * math.TAU,
            }
            asset.header.bounds_min[0] = min(asset.header.bounds_min[0], position[0])
            asset.header.bounds_min[1] = min(asset.header.bounds_min[1], position[1])
            asset.header.bounds_min[2] = min(asset.header.bounds_min[2], position[2])
            asset.header.bounds_max[0] = max(asset.header.bounds_max[0], position[0])
            asset.header.bounds_max[1] = max(asset.header.bounds_max[1], position[1])
            asset.header.bounds_max[2] = max(asset.header.bounds_max[2], position[2])
        }
        append(&lod.indices, ..mesh.indices[:])
        for attachment, attachment_index in result.plant.attachments {
            architecture_kind := plants.Architecture_Organ.Leaf
            if attachment_index < len(result.plant.graph.organs) {
                architecture_kind = result.plant.graph.organs[attachment_index].kind
            }
            append(
                &lod.organs,
                Plant_Asset_Organ {
                    position = attachment.position,
                    forward = attachment.forward,
                    up = attachment.up,
                    stable_id = result.plant.attachment_ids[attachment_index],
                    kind = attachment.kind,
                    stage = attachment.stage,
                    depth = i32(attachment.depth),
                    variant = attachment.variant,
                    leaf_shape = u8(attachment.leaf.shape),
                    leaf_length = attachment.leaf.length,
                    leaf_width = attachment.leaf.width,
                    leaf_serration = attachment.leaf.serration,
                    leaf_curl = attachment.leaf.curl,
                    leaf_cup = attachment.leaf.cup,
                    leaf_thickness = attachment.leaf.thickness,
                    architecture_kind = architecture_kind,
                },
            )
        }
        if lod_index == 0 {
            asset.header.radial_irregularity = result.plant.wood.radial_irregularity
            asset.header.bark_twist = result.plant.wood.twist
            asset.header.wind_compliance = result.plant.wind_compliance
            asset.header.root_kind = result.plant.root_kind
            asset.header.support_signature = result.plant.support_signature
        }
        branch_mesh.destroy(&mesh)
        plants.destroy(&result)
    }
    asset.header.impostor_pivot = {
        (asset.header.bounds_min[0] + asset.header.bounds_max[0]) * .5,
        asset.header.bounds_min[1],
        (asset.header.bounds_min[2] + asset.header.bounds_max[2]) * .5,
    }
    asset.header.bark_material_ref = u32(request.species) * 2 + 1
    asset.header.organ_material_ref = u32(request.species) * 2 + 2
    asset.header.collision_radius = max(
        max(math.abs(asset.header.bounds_min[0]), math.abs(asset.header.bounds_max[0])),
        max(math.abs(asset.header.bounds_min[2]), math.abs(asset.header.bounds_max[2])),
    )
    asset.header.collision_height = max(asset.header.bounds_max[1] - asset.header.bounds_min[1], f32(0))
    elevation_angles := [PLANT_IMPOSTOR_ELEVATION_COUNT]f32{-15, 15, 45}
    for elevation in 0 ..< PLANT_IMPOSTOR_ELEVATION_COUNT {
        for azimuth in 0 ..< PLANT_IMPOSTOR_AZIMUTH_COUNT {
            index := elevation * PLANT_IMPOSTOR_AZIMUTH_COUNT + azimuth
            asset.header.impostor_views[index] = {
                azimuth    = f32(azimuth) * math.TAU / PLANT_IMPOSTOR_AZIMUTH_COUNT,
                elevation  = elevation_angles[elevation] * math.PI / 180,
                uv_min     = {
                    f32(azimuth) / PLANT_IMPOSTOR_AZIMUTH_COUNT,
                    f32(elevation) / PLANT_IMPOSTOR_ELEVATION_COUNT,
                },
                uv_max     = {
                    f32(azimuth + 1) / PLANT_IMPOSTOR_AZIMUTH_COUNT,
                    f32(elevation + 1) / PLANT_IMPOSTOR_ELEVATION_COUNT,
                },
                bounds_min = asset.header.bounds_min,
                bounds_max = asset.header.bounds_max,
                pivot      = asset.header.impostor_pivot,
            }
        }
    }
    plant_asset_generate_impostors(&asset)
    return asset, true
}

plant_impostor_select :: proc(camera_azimuth, camera_elevation: f32) -> Plant_Impostor_Selection {
    azimuth := camera_azimuth
    for azimuth < 0 do azimuth += math.TAU
    for azimuth >= math.TAU do azimuth -= math.TAU
    azimuth_position := azimuth / math.TAU * PLANT_IMPOSTOR_AZIMUTH_COUNT
    first_azimuth := int(math.floor(azimuth_position)) % PLANT_IMPOSTOR_AZIMUTH_COUNT
    second_azimuth := (first_azimuth + 1) % PLANT_IMPOSTOR_AZIMUTH_COUNT
    blend := azimuth_position - math.floor(azimuth_position)
    elevation := camera_elevation * 180 / math.PI
    elevation_band := elevation < 0 ? 0 : elevation < 30 ? 1 : 2
    offset := elevation_band * PLANT_IMPOSTOR_AZIMUTH_COUNT
    return {first = offset + first_azimuth, second = offset + second_azimuth, blend = blend}
}

plant_asset_append_bytes :: #force_inline proc(output: ^[dynamic]byte, value: rawptr, count: int) {
    bytes := ([^]byte)(value)
    append(output, ..bytes[:count])
}

plant_asset_serialize :: proc(asset: ^Plant_Asset) -> [dynamic]byte {
    output := make([dynamic]byte)
    if asset == nil do return output
    header := asset.header
    offset := u64(size_of(Plant_Asset_Header))
    for &lod, lod_index in header.lods {
        payload := &asset.lods[lod_index]
        lod.segment_count = u32(len(payload.segments))
        lod.vertex_count = u32(len(payload.vertices))
        lod.index_count = u32(len(payload.indices))
        lod.organ_count = u32(len(payload.organs))
        lod.segment_offset = offset
        offset += u64(len(payload.segments) * size_of(Plant_Asset_Segment))
        lod.vertex_offset = offset
        offset += u64(len(payload.vertices) * size_of(Plant_Asset_Vertex))
        lod.index_offset = offset
        offset += u64(len(payload.indices) * size_of(u32))
        lod.organ_offset = offset
        offset += u64(len(payload.organs) * size_of(Plant_Asset_Organ))
    }
    header.impostor_color_offset = offset
    header.impostor_color_size = u64(len(asset.impostor_color))
    offset += header.impostor_color_size
    header.impostor_normal_offset = offset
    header.impostor_normal_size = u64(len(asset.impostor_normal))
    plant_asset_append_bytes(&output, &header, size_of(header))
    for &payload in asset.lods {
        if len(payload.segments) > 0 do plant_asset_append_bytes(&output, raw_data(payload.segments), len(payload.segments) * size_of(Plant_Asset_Segment))
        if len(payload.vertices) > 0 do plant_asset_append_bytes(&output, raw_data(payload.vertices), len(payload.vertices) * size_of(Plant_Asset_Vertex))
        if len(payload.indices) > 0 do plant_asset_append_bytes(&output, raw_data(payload.indices), len(payload.indices) * size_of(u32))
        if len(payload.organs) > 0 do plant_asset_append_bytes(&output, raw_data(payload.organs), len(payload.organs) * size_of(Plant_Asset_Organ))
    }
    if len(asset.impostor_color) > 0 do plant_asset_append_bytes(&output, raw_data(asset.impostor_color), len(asset.impostor_color))
    if len(asset.impostor_normal) > 0 do plant_asset_append_bytes(&output, raw_data(asset.impostor_normal), len(asset.impostor_normal))
    checksum := u64(1469598103934665603)
    for value in output[size_of(Plant_Asset_Header):] do checksum = (checksum ~ u64(value)) * 1099511628211
    header.payload_checksum = checksum
    header_bytes := ([^]byte)(rawptr(&header))
    copy(output[:size_of(header)], header_bytes[:size_of(header)])
    return output
}

plant_asset_validate_bytes :: proc(data: []byte) -> bool {
    if len(data) < size_of(Plant_Asset_Header) do return false
    header := (^Plant_Asset_Header)(raw_data(data))^
    if header.magic != PLANT_ASSET_MAGIC ||
       header.format_version != PLANT_ASSET_FORMAT_VERSION ||
       header.generator_version != PLANT_GENERATOR_VERSION ||
       header.impostor_azimuths != PLANT_IMPOSTOR_AZIMUTH_COUNT ||
       header.impostor_elevations != PLANT_IMPOSTOR_ELEVATION_COUNT ||
       header.impostor_width != PLANT_IMPOSTOR_ATLAS_WIDTH ||
       header.impostor_height != PLANT_IMPOSTOR_ATLAS_HEIGHT ||
       header.bark_material_ref == 0 ||
       header.organ_material_ref == 0 ||
       header.collision_radius <= 0 ||
       header.collision_height <= 0 {
        return false
    }
    if header.source_key != plant_asset_source_key(header.request) do return false
    data_size := u64(len(data))
    for lod in header.lods {
        segment_bytes := u64(lod.segment_count) * size_of(Plant_Asset_Segment)
        vertex_bytes := u64(lod.vertex_count) * size_of(Plant_Asset_Vertex)
        index_bytes := u64(lod.index_count) * size_of(u32)
        organ_bytes := u64(lod.organ_count) * size_of(Plant_Asset_Organ)
        if lod.segment_offset < size_of(Plant_Asset_Header) ||
           lod.segment_offset + segment_bytes > data_size ||
           lod.vertex_offset < lod.segment_offset + segment_bytes ||
           lod.vertex_offset + vertex_bytes > data_size ||
           lod.index_offset < lod.vertex_offset + vertex_bytes ||
           lod.index_offset + index_bytes > data_size ||
           lod.organ_offset < lod.index_offset + index_bytes ||
           lod.organ_offset + organ_bytes > data_size {
            return false
        }
    }
    expected_atlas_size := u64(PLANT_IMPOSTOR_ATLAS_WIDTH * PLANT_IMPOSTOR_ATLAS_HEIGHT * 4)
    if header.impostor_color_size != expected_atlas_size ||
       header.impostor_normal_size != expected_atlas_size ||
       header.impostor_color_offset < size_of(Plant_Asset_Header) ||
       header.impostor_color_offset + header.impostor_color_size > data_size ||
       header.impostor_normal_offset != header.impostor_color_offset + header.impostor_color_size ||
       header.impostor_normal_offset + header.impostor_normal_size > data_size {
        return false
    }
    checksum := u64(1469598103934665603)
    for value in data[size_of(Plant_Asset_Header):] do checksum = (checksum ~ u64(value)) * 1099511628211
    return checksum == header.payload_checksum
}

plant_asset_lod_index_for_detail :: #force_inline proc(detail: plants.Detail_Level) -> int {
    switch detail {
    case .Near:
        return 1
    case .Medium:
        return 2
    case .Far:
        return 3
    }
    return 3
}

plant_asset_generated_result :: proc(data: []byte, detail: plants.Detail_Level) -> (plants.Generate_Result, bool) {
    result: plants.Generate_Result
    if !plant_asset_validate_bytes(data) do return result, false
    header := (^Plant_Asset_Header)(raw_data(data))^
    lod := header.lods[plant_asset_lod_index_for_detail(detail)]
    byte_base := uintptr(raw_data(data))
    segments := ([^]Plant_Asset_Segment)(byte_base + uintptr(lod.segment_offset))[:lod.segment_count]
    organs := ([^]Plant_Asset_Organ)(byte_base + uintptr(lod.organ_offset))[:lod.organ_count]
    plant := &result.plant
    plant.species = header.request.species
    plant.habit = header.request.habit
    plant.maturity = f32(header.request.maturity_step) / PLANT_MATURITY_STEPS
    plant.bounds = {
        minimum = header.bounds_min,
        maximum = header.bounds_max,
    }
    plant.wood = {
        radial_irregularity = header.radial_irregularity,
        twist               = header.bark_twist,
    }
    plant.root_kind = header.root_kind
    plant.wind_compliance = header.wind_compliance
    plant.support_signature = header.support_signature
    plant.segments = make([dynamic]plant_structure.Segment, 0, len(segments))
    plant.segment_parents = make([dynamic]int, 0, len(segments))
    plant.segment_axes = make([dynamic]int, 0, len(segments))
    plant.segment_ids = make([dynamic]u64, 0, len(segments))
    axis_count := 0
    for segment in segments do axis_count = max(axis_count, int(segment.axis) + 1)
    plant.axis_parents = make([dynamic]int, axis_count)
    plant.axis_roles = make([dynamic]plants.Axis_Role, axis_count)
    plant.axis_orientations = make([dynamic]plants.Axis_Orientation, axis_count)
    axis_seen := make([]bool, axis_count)
    defer delete(axis_seen)
    for segment in segments {
        append(
            &plant.segments,
            plant_structure.Segment {
                start = segment.start,
                end = segment.end,
                radius_start = segment.radius_start,
                radius_end = segment.radius_end,
                depth = int(segment.depth),
            },
        )
        append(&plant.segment_parents, int(segment.parent))
        append(&plant.segment_axes, int(segment.axis))
        append(&plant.segment_ids, segment.stable_id)
        axis := int(segment.axis)
        if axis >= 0 && axis < axis_count && !axis_seen[axis] {
            plant.axis_parents[axis] = int(segment.axis_parent)
            plant.axis_roles[axis] = segment.axis_role
            plant.axis_orientations[axis] = segment.axis_orientation
            axis_seen[axis] = true
        }
    }
    plant.attachments = make([dynamic]plants.Attachment, 0, len(organs))
    plant.attachment_ids = make([dynamic]u64, 0, len(organs))
    for organ in organs {
        append(
            &plant.attachments,
            plants.Attachment {
                kind = organ.kind,
                stage = organ.stage,
                position = organ.position,
                forward = organ.forward,
                up = organ.up,
                depth = int(organ.depth),
                variant = organ.variant,
                leaf = {
                    shape = leaf_mesh.Shape(organ.leaf_shape),
                    length = organ.leaf_length,
                    width = organ.leaf_width,
                    serration = organ.leaf_serration,
                    curl = organ.leaf_curl,
                    cup = organ.leaf_cup,
                    thickness = organ.leaf_thickness,
                },
            },
        )
        append(&plant.attachment_ids, organ.stable_id)
    }
    plants.generated_graph_build(plant, header.request.seed)
    for axis_index in 0 ..< axis_count {
        for segment in segments {
            if int(segment.axis) != axis_index do continue
            plant.graph.axes[axis_index].stable_id = segment.axis_stable_id
            plant.graph.growth_units[axis_index].stable_id = segment.growth_stable_id
            break
        }
    }
    for &bud in plant.graph.buds {
        source := segments[bud.internode]
        if source.bud_stable_id != 0 {
            bud.stable_id = source.bud_stable_id
            bud.state = source.bud_state
        }
    }
    for &graph_organ, index in plant.graph.organs {
        graph_organ.kind = organs[index].architecture_kind
        graph_organ.stable_id = organs[index].stable_id
    }
    return result, true
}

plant_asset_mesh_from_bytes :: proc(data: []byte, detail: plants.Detail_Level) -> (Plant_Asset_Mesh, bool) {
    mesh: Plant_Asset_Mesh
    if !plant_asset_validate_bytes(data) do return mesh, false
    header := (^Plant_Asset_Header)(raw_data(data))^
    lod := header.lods[plant_asset_lod_index_for_detail(detail)]
    byte_base := uintptr(raw_data(data))
    vertices := ([^]Plant_Asset_Vertex)(byte_base + uintptr(lod.vertex_offset))[:lod.vertex_count]
    indices := ([^]u32)(byte_base + uintptr(lod.index_offset))[:lod.index_count]
    mesh.vertices = make([dynamic]Plant_Asset_Vertex, len(vertices))
    mesh.indices = make([dynamic]u32, len(indices))
    copy(mesh.vertices[:], vertices)
    copy(mesh.indices[:], indices)
    color := ([^]byte)(byte_base + uintptr(header.impostor_color_offset))[:header.impostor_color_size]
    normal := ([^]byte)(byte_base + uintptr(header.impostor_normal_offset))[:header.impostor_normal_size]
    mesh.impostor_color = make([dynamic]byte, len(color))
    mesh.impostor_normal = make([dynamic]byte, len(normal))
    copy(mesh.impostor_color[:], color)
    copy(mesh.impostor_normal[:], normal)
    mesh.impostor_views = header.impostor_views
    mesh.impostor_width = int(header.impostor_width)
    mesh.impostor_height = int(header.impostor_height)
    return mesh, true
}

plant_asset_try_load :: proc(
    request: Plant_Asset_Request,
    detail: plants.Detail_Level,
) -> (
    plants.Generate_Result,
    Plant_Asset_Mesh,
    bool,
) {
    key := plant_asset_source_key(request)
    paths := [2]string {
        fmt.tprintf("assets/generated/plants/%016x.plant", key),
        fmt.tprintf("build/dev/assets/generated/plants/%016x.plant", key),
    }
    for path in paths {
        data, read_error := os.read_entire_file(path, context.temp_allocator)
        if read_error != nil do continue
        result, result_ok := plant_asset_generated_result(data, detail)
        if !result_ok do return {}, {}, false
        mesh, mesh_ok := plant_asset_mesh_from_bytes(data, detail)
        if !mesh_ok {
            plants.destroy(&result)
            return {}, {}, false
        }
        return result, mesh, true
    }
    return {}, {}, false
}

plant_asset_compile_cli :: proc(args: []string) -> bool {
    output_directory := "assets/generated/plants"
    if len(args) == 4 && args[2] == "--output" do output_directory = args[3]
    if len(args) != 2 && len(args) != 4 {
        fmt.eprintln("adriatic plant-compile accepts only --output <directory>")
        return false
    }
    if err := os.make_directory_all(output_directory); err != nil && err != .Exist {
        fmt.eprintf("plant-compile: cannot create %s: %v\n", output_directory, err)
        return false
    }
    if !plant_asset_manifest_valid() {
        fmt.eprintln("plant-compile: source manifest is invalid")
        return false
    }
    manifest := plant_asset_manifest_requests(context.temp_allocator)
    compiled := 0
    for request in manifest {
        species := request.species
        asset, ok := plant_asset_compile(request)
        if !ok {
            fmt.eprintf("plant-compile: failed for %s\n", plants.species_name(species))
            return false
        }
        bytes := plant_asset_serialize(&asset)
        path := fmt.tprintf("%s/%016x.plant", output_directory, asset.header.source_key)
        write_error := os.write_entire_file(path, bytes[:])
        delete(bytes)
        plant_asset_destroy(&asset)
        if write_error != nil {
            fmt.eprintf("plant-compile: cannot write %s: %v\n", path, write_error)
            return false
        }
        compiled += 1
    }
    pattern := fmt.tprintf("%s/*.plant", output_directory)
    existing, glob_error := os.glob(pattern, context.temp_allocator)
    if glob_error != nil {
        fmt.eprintf("plant-compile: cannot audit %s: %v\n", output_directory, glob_error)
        return false
    }
    removed := 0
    for path in existing {
        retained := false
        for request in manifest {
            expected := fmt.tprintf("%s/%016x.plant", output_directory, plant_asset_source_key(request))
            if path == expected {
                retained = true
                break
            }
        }
        if retained do continue
        if remove_error := os.remove(path); remove_error != nil {
            fmt.eprintf("plant-compile: cannot remove stale asset %s: %v\n", path, remove_error)
            return false
        }
        removed += 1
    }
    fmt.printf("plant-compile: wrote %d assets to %s (%d stale removed)\n", compiled, output_directory, removed)
    return true
}
