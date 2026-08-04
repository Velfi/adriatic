package plant_assets

import branch_mesh "../branch_mesh"
import leaf_mesh "../leaf_mesh"
import plant_structure "../plant_structure"
import plants "../plants"
import "core:fmt"
import "core:math"
import "core:os"

PLANT_ASSET_MAGIC :: u64(0x544e414c50524441) // "ADRPLANT" little-endian
PLANT_ASSET_FORMAT_VERSION :: u32(4)
PLANT_GENERATOR_VERSION :: u32(1)
PLANT_ASSET_LOD_COUNT :: 5
PLANT_IMPOSTOR_AZIMUTH_COUNT :: 8
PLANT_IMPOSTOR_ELEVATION_COUNT :: 3
PLANT_IMPOSTOR_VIEW_COUNT :: PLANT_IMPOSTOR_AZIMUTH_COUNT * PLANT_IMPOSTOR_ELEVATION_COUNT
PLANT_MATURITY_STEPS :: 5

Plant_Asset_Request :: struct {
    species:        plants.Species,
    seed:           u64,
    maturity_step:  u8,
    habit:          plants.Growth_Habit,
    site_signature: u64,
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
    magic:               u64,
    format_version:      u32,
    generator_version:   u32,
    source_key:          u64,
    request:             Plant_Asset_Request,
    bounds_min:          [3]f32,
    bounds_max:          [3]f32,
    radial_irregularity: f32,
    bark_twist:          f32,
    wind_compliance:     f32,
    root_kind:           plants.Root_Kind,
    support_signature:   u64,
    lods:                [PLANT_ASSET_LOD_COUNT]Plant_Asset_LOD_Header,
    impostor_azimuths:   u8,
    impostor_elevations: u8,
    impostor_pivot:      [3]f32,
    impostor_views:      [PLANT_IMPOSTOR_VIEW_COUNT]Plant_Impostor_View,
    payload_checksum:    u64,
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
    header: Plant_Asset_Header,
    lods:   [PLANT_ASSET_LOD_COUNT]Plant_Asset_LOD,
}

Plant_Asset_Mesh :: struct {
    vertices: [dynamic]Plant_Asset_Vertex,
    indices:  [dynamic]u32,
}

plant_asset_mesh_destroy :: proc(mesh: ^Plant_Asset_Mesh) {
    if mesh == nil do return
    delete(mesh.vertices)
    delete(mesh.indices)
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
    return plant_asset_hash_u64(hash, request.site_signature)
}

plant_asset_detail :: #force_inline proc(lod: int) -> plants.Detail_Level {
    if lod <= 1 do return .Near
    if lod == 2 do return .Medium
    return .Far
}

plant_asset_compile :: proc(request: Plant_Asset_Request) -> (Plant_Asset, bool) {
    asset: Plant_Asset
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
            },
        )
        if result.error != .None {
            plants.destroy(&result)
            plant_asset_destroy(&asset)
            return {}, false
        }
        mesh := branch_mesh.generate(
            result.plant.segments[:],
            {
                radial_segments = lod_index == 0 ? 10 : lod_index == 1 ? 8 : lod_index == 2 ? 6 : 4,
                samples_per_segment = lod_index == 0 ? 4 : lod_index == 1 ? 3 : lod_index == 2 ? 2 : 1,
                minimum_radius = .0005,
                seed = request.seed,
                axis_ids = result.plant.segment_axes[:],
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
            lod.vertices[vertex_index] = {
                position         = position,
                normal           = source.normal,
                uv               = source.bark_uv,
                primary_anchor   = {position[0], 0, position[2]},
                secondary_anchor = position,
                axis_position    = position[1],
                stiffness        = 1 / (1 + max(position[1], f32(0)) * .18),
                hierarchy_depth  = 0,
                phase            = f32((request.seed + u64(vertex_index) * 17) & 0xffff) / 65535 * math.TAU,
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
    plant_asset_append_bytes(&output, &header, size_of(header))
    for &payload in asset.lods {
        if len(payload.segments) > 0 do plant_asset_append_bytes(&output, raw_data(payload.segments), len(payload.segments) * size_of(Plant_Asset_Segment))
        if len(payload.vertices) > 0 do plant_asset_append_bytes(&output, raw_data(payload.vertices), len(payload.vertices) * size_of(Plant_Asset_Vertex))
        if len(payload.indices) > 0 do plant_asset_append_bytes(&output, raw_data(payload.indices), len(payload.indices) * size_of(u32))
        if len(payload.organs) > 0 do plant_asset_append_bytes(&output, raw_data(payload.organs), len(payload.organs) * size_of(Plant_Asset_Organ))
    }
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
       header.impostor_elevations != PLANT_IMPOSTOR_ELEVATION_COUNT {
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
    compiled := 0
    for request in PLANT_ASSET_MANIFEST {
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
    fmt.printf("plant-compile: wrote %d assets to %s\n", compiled, output_directory)
    return true
}
