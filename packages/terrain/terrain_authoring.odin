package terrain

import "core:math"

Authoring_Preview_Quality :: enum u8 {
    Interactive,
    Final,
}
AUTHORING_BRUSH_MAX_FLOW :: f32(8)

Authoring_Brush_Operation :: enum u8 {
    Coast,
    Shelf,
    Relax,
    Erode,
    Deposit,
    Roughen,
    Terrace,
    Cut_Fill,
}
Authoring_Spline_Operation :: enum u8 {
    Ridge,
    Valley,
    Slope,
    Grade,
}
Authoring_Profile :: enum u8 {
    Round,
    Sharp,
    Cliff,
}

Authoring_Brush_Request :: struct {
    owner:                 Island_ID,
    operation:             Authoring_Brush_Operation,
    world_x, world_z:      f32,
    size:                  f32,
    inner_core:            f32,
    feather:               f32,
    flow:                  f32,
    direction:             f32,
    affect_seabed:         bool,
    target_height:         f32,
    beach_height:          f32,
    shelf_depth:           f32,
    shelf_slope:           f32,
    talus:                 f32,
    iterations:            int,
    rainfall:              f32,
    sediment_capacity:     f32,
    amplitude:             f32,
    noise_scale:           f32,
    octaves:               int,
    seed:                  u32,
    terrace_height:        f32,
    terrace_reference:     f32,
    terrace_depth:         f32,
    retaining_slope:       f32,
    irregularity:          f32,
    cut_limit, fill_limit: f32,
    preserve_coastline:    bool,
    quality:               Authoring_Preview_Quality,
    authored_level:        int,
    single_level:          bool,
}

Authoring_Spline_Request :: struct {
    owner:                    Island_ID,
    operation:                Authoring_Spline_Operation,
    points:                   []Cliff_Point,
    width, feather, flow:     f32,
    height:                   f32,
    side_bias:                f32,
    roughness:                f32,
    endpoint_taper:           f32,
    start_height, end_height: f32,
    maximum_grade:            f32,
    preserve_detail:          f32,
    affect_seabed:            bool,
    profile:                  Authoring_Profile,
    seed:                     u32,
    authored_level:           int,
    single_level:             bool,
}

Authoring_Area_Request :: struct {
    owner:                 Island_ID,
    start_x, start_z:      f32,
    end_x, end_z:          f32,
    target_height:         f32,
    feather:               f32,
    flow:                  f32,
    corner_radius:         f32,
    affect_seabed:         bool,
    cut_limit, fill_limit: f32,
    authored_level:        int,
    single_level:          bool,
}

Authoring_Volume :: struct {
    cut, fill: f32,
}

authoring_mask :: #force_inline proc(distance, size, inner_core, feather: f32) -> f32 {
    outer := size + max(feather, f32(0))
    if size <= 0 || distance >= outer do return 0
    core := clamp(inner_core, f32(0), f32(1)) * size
    if distance <= core do return 1
    edge := max(outer - core, f32(.001))
    t := clamp((distance - core) / edge, f32(0), f32(1))
    return 1 - (t * t * (3 - 2 * t))
}

authoring_hash :: #force_inline proc(x: u32) -> u32 {
    value := x
    value = (value ~ (value >> 16)) * 0x7feb352d
    value = (value ~ (value >> 15)) * 0x846ca68b
    return value ~ (value >> 16)
}

authoring_noise :: proc(x, z: f32, scale: f32, octaves: int, seed: u32) -> f32 {
    frequency := 1 / max(scale, f32(1))
    amplitude := f32(1)
    total, normalization := f32(0), f32(0)
    for octave in 0 ..< clamp(octaves, 1, 6) {
        gx, gz := i32(math.floor(f64(x * frequency))), i32(math.floor(f64(z * frequency)))
        hash := authoring_hash(u32(gx) * 0x9e3779b9 ~ u32(gz) * 0x85ebca6b ~ seed ~ u32(octave))
        value := f32(hash & 0xffff) / 32767.5 - 1
        total += value * amplitude
        normalization += amplitude
        frequency *= 2
        amplitude *= .5
    }
    return normalization > 0 ? total / normalization : 0
}

authoring_land_allowed :: #force_inline proc(project: ^Project, height: f32, affect_seabed: bool) -> bool {
    return affect_seabed || height > project.sea_level + SHORELINE_EPSILON
}

authoring_level_is_finest_at :: #force_inline proc(project: ^Project, level: int, x, z: f32) -> bool {
    for finer in 0 ..< level {
        if level_contains(&project.levels[finer], x, z) do return false
    }
    return true
}

authoring_refresh_derived_bounds :: proc(project: ^Project, min_x, min_z, max_x, max_z: f32) {
    for level in 1 ..< CLIPMAP_LEVELS {
        finer := &project.levels[level - 1]
        coarse := &project.levels[level]
        x0, z0, x1, z1, overlaps := level_sample_bounds(coarse, min_x, min_z, max_x, max_z)
        if !overlaps do continue
        for z in z0 ..= z1 {
            sample_z := coarse.origin_z + f32(z) * coarse.cell_size
            for x in x0 ..= x1 {
                sample_x := coarse.origin_x + f32(x) * coarse.cell_size
                if !level_contains(finer, sample_x, sample_z) do continue
                index := sample_index(x, z)
                coarse.heights[index] = sample_level_height(finer, sample_x, sample_z)
                coarse.material[index] = sample_level_material(finer, sample_x, sample_z)
            }
        }
    }
}

apply_authoring_brush :: proc(project: ^Project, request: Authoring_Brush_Request) -> bool {
    if project == nil do return false
    if !request.single_level {
        changed := false
        for level in 0 ..< CLIPMAP_LEVELS {
            level_request := request
            level_request.authored_level = level
            level_request.single_level = true
            changed = apply_authoring_brush(project, level_request) || changed
        }
        if changed {
            source_x, source_z, valid := terrain_operator_source_point(
                project,
                request.owner,
                request.world_x,
                request.world_z,
            )
            if valid {
                outer := request.size + max(request.feather, f32(0))
                authoring_refresh_derived_bounds(
                    project,
                    source_x - outer,
                    source_z - outer,
                    source_x + outer,
                    source_z + outer,
                )
            }
            project.revision += 1
        }
        return changed
    }
    source_x, source_z, valid := terrain_operator_source_point(
        project,
        request.owner,
        request.world_x,
        request.world_z,
    )
    if !valid || request.size <= 0 || request.flow <= 0 do return false
    outer := request.size + max(request.feather, f32(0))
    authored := clamp(request.authored_level, 0, CLIPMAP_LEVELS - 1)
    data := &project.levels[authored]
    radius := max(outer, data.cell_size * 1.5)
    min_x, min_z, max_x, max_z, overlaps := level_sample_bounds(
        data,
        source_x - radius,
        source_z - radius,
        source_x + radius,
        source_z + radius,
    )
    if !overlaps do return false
    width, height := max_x - min_x + 1, max_z - min_z + 1
    source := make([]f32, width * height)
    defer delete(source)
    water := make([]f32, width * height)
    sediment := make([]f32, width * height)
    defer delete(water)
    defer delete(sediment)
    for z in min_z ..= max_z do for x in min_x ..= max_x {
        source[(z - min_z) * width + x - min_x] = data.heights[sample_index(x, z)]
    }
    iterations := clamp(request.iterations, 1, request.quality == .Interactive ? 8 : 96)
    changed := false
    for iteration in 0 ..< iterations {
        for z in min_z ..= max_z {
            sample_z := data.origin_z + f32(z) * data.cell_size
            for x in min_x ..= max_x {
                sample_x := data.origin_x + f32(x) * data.cell_size
                if !authoring_level_is_finest_at(project, authored, sample_x, sample_z) do continue
                dx, dz := sample_x - source_x, sample_z - source_z
                distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
                mask :=
                    authoring_mask(distance, request.size, request.inner_core, request.feather) *
                    clamp(request.flow, f32(0), AUTHORING_BRUSH_MAX_FLOW) /
                    f32(iterations)
                index := sample_index(x, z)
                current := data.heights[index]
                if mask <= 0 || !authoring_land_allowed(project, current, request.affect_seabed) do continue
                next := current
                switch request.operation {
                case .Coast:
                    // High-strength coastal strokes need to reach existing
                    // land, not just the default beach/shelf elevation band.
                    coastal_range :=
                        max(request.beach_height + abs(request.shelf_depth), f32(1)) *
                        max(clamp(request.flow, f32(0), AUTHORING_BRUSH_MAX_FLOW), f32(1))
                    coastal := clamp(
                        1 -
                        abs(current - project.sea_level) /
                            coastal_range,
                        f32(0),
                        f32(1),
                    )
                    next += request.direction * max(request.beach_height, f32(1)) * mask * coastal
                case .Shelf:
                    normalized := clamp(distance / radius, f32(0), f32(1))
                    target :=
                        project.sea_level +
                        request.beach_height +
                        (request.shelf_depth - request.beach_height) *
                            f32(math.pow(f64(normalized), f64(max(request.shelf_slope, f32(.1)))))
                    next += (target - current) * mask
                case .Relax, .Erode, .Deposit:
                    local := (z - min_z) * width + x - min_x
                    left := source[(z - min_z) * width + clamp(x - 1, min_x, max_x) - min_x]
                    right := source[(z - min_z) * width + clamp(x + 1, min_x, max_x) - min_x]
                    up := source[(clamp(z - 1, min_z, max_z) - min_z) * width + x - min_x]
                    down := source[(clamp(z + 1, min_z, max_z) - min_z) * width + x - min_x]
                    average := (left + right + up + down) * .25
                    delta := average - source[local]
                    if request.operation == .Relax && abs(delta) > request.talus do next += delta * mask
                    if request.operation == .Erode {
                        water[local] += max(request.rainfall, f32(.01)) / f32(iterations)
                        center := source[local]
                        lowest, lowest_index := center, local
                        if left <
                           lowest { lowest = left; lowest_index = (z - min_z) * width + clamp(x - 1, min_x, max_x) - min_x }
                        if right <
                           lowest { lowest = right; lowest_index = (z - min_z) * width + clamp(x + 1, min_x, max_x) - min_x }
                        if up <
                           lowest { lowest = up; lowest_index = (clamp(z - 1, min_z, max_z) - min_z) * width + x - min_x }
                        if down <
                           lowest { lowest = down; lowest_index = (clamp(z + 1, min_z, max_z) - min_z) * width + x - min_x }
                        slope := max(center - lowest - request.talus, f32(0))
                        capacity := water[local] * slope * max(request.sediment_capacity, f32(.01))
                        eroded := max(capacity - sediment[local], f32(0)) * .22 * mask
                        deposited := max(sediment[local] - capacity, f32(0)) * .18 * mask
                        next += deposited - eroded
                        sediment[local] += eroded - deposited
                        if lowest_index != local {
                            transfer := sediment[local] * .35
                            sediment[local] -= transfer
                            sediment[lowest_index] += transfer
                            water[lowest_index] += water[local] * .4
                        }
                        water[local] *= .82
                    }
                    if request.operation == .Deposit && delta > request.talus do next += delta * mask
                case .Roughen:
                    next +=
                        authoring_noise(sample_x, sample_z, request.noise_scale, request.octaves, request.seed) *
                        request.amplitude *
                        mask
                case .Terrace:
                    interval := max(request.terrace_height, f32(.1))
                    irregular :=
                        authoring_noise(sample_x, sample_z, max(request.terrace_depth, f32(1)), 2, request.seed) *
                        request.irregularity *
                        interval *
                        .35
                    target :=
                        request.terrace_reference +
                        irregular +
                        f32(math.round(f64((current - request.terrace_reference - irregular) / interval))) * interval
                    retaining := .25 + clamp(request.retaining_slope, f32(0), f32(1)) * .75
                    next += (target - current) * mask * retaining
                case .Cut_Fill:
                    delta := request.target_height - current
                    delta =
                        delta < 0 ? max(delta, -max(request.cut_limit, f32(0))) : min(delta, max(request.fill_limit, f32(0)))
                    next += delta * mask
                }
                if request.preserve_coastline && (current - project.sea_level) * (next - project.sea_level) < 0 do next = project.sea_level
                if abs(next - current) > .00001 {
                    data.heights[index] = next
                    changed = true
                }
            }
        }
        if request.operation == .Relax || request.operation == .Erode || request.operation == .Deposit {
            for z in min_z ..= max_z do for x in min_x ..= max_x {
                source[(z - min_z) * width + x - min_x] = data.heights[sample_index(x, z)]
            }
        }
    }
    if !changed do return false
    return true
}

authoring_closest_spline :: proc(
    points: []Cliff_Point,
    x, z: f32,
) -> (
    distance, signed_distance, path_t: f32,
    ok: bool,
) {
    if len(points) < 2 do return 0, 0, 0, false
    best_squared := f32(3.4e38)
    travelled, total := f32(0), f32(0)
    for index in 0 ..< len(points) - 1 {
        dx, dz := points[index + 1].x - points[index].x, points[index + 1].z - points[index].z
        total += f32(math.sqrt(f64(dx * dx + dz * dz)))
    }
    for index in 0 ..< len(points) - 1 {
        a, b := points[index], points[index + 1]
        dx, dz := b.x - a.x, b.z - a.z
        length_squared := dx * dx + dz * dz
        if length_squared <= .0001 do continue
        segment_length := f32(math.sqrt(f64(length_squared)))
        t := clamp(((x - a.x) * dx + (z - a.z) * dz) / length_squared, f32(0), f32(1))
        ox, oz := x - (a.x + dx * t), z - (a.z + dz * t)
        squared := ox * ox + oz * oz
        if squared < best_squared {
            best_squared = squared
            distance = f32(math.sqrt(f64(squared)))
            signed_distance = (dx * oz - dz * ox) / segment_length
            path_t = total > 0 ? (travelled + segment_length * t) / total : 0
            ok = true
        }
        travelled += segment_length
    }
    return
}

apply_authoring_spline :: proc(project: ^Project, request: Authoring_Spline_Request) -> bool {
    if project == nil || len(request.points) < 2 || request.width <= 0 || request.flow <= 0 do return false
    if !request.single_level {
        changed := false
        for level in 0 ..< CLIPMAP_LEVELS {
            level_request := request
            level_request.authored_level = level
            level_request.single_level = true
            changed = apply_authoring_spline(project, level_request) || changed
        }
        if changed {
            owner_index, owner_ok := island_index(request.owner)
            if owner_ok {
                transform := island_transform_at(project, owner_index)
                offset_x, offset_z :=
                    transform.current_x - transform.source_x, transform.current_z - transform.source_z
                min_x, max_x := request.points[0].x - offset_x, request.points[0].x - offset_x
                min_z, max_z := request.points[0].z - offset_z, request.points[0].z - offset_z
                for point in request.points[1:] {
                    min_x = min(min_x, point.x - offset_x)
                    max_x = max(max_x, point.x - offset_x)
                    min_z = min(min_z, point.z - offset_z)
                    max_z = max(max_z, point.z - offset_z)
                }
                outer := request.width * .5 + max(request.feather, f32(0))
                authoring_refresh_derived_bounds(project, min_x - outer, min_z - outer, max_x + outer, max_z + outer)
            }
            project.revision += 1
        }
        return changed
    }
    owner_index, owner_ok := island_index(request.owner)
    if !owner_ok do return false
    transform := island_transform_at(project, owner_index)
    offset_x, offset_z := transform.current_x - transform.source_x, transform.current_z - transform.source_z
    points := make([]Cliff_Point, len(request.points)); defer delete(points)
    for point, index in request.points {
        if island_at(project, point.x, point.z) != request.owner do return false
        points[index] = {point.x - offset_x, point.z - offset_z}
    }
    min_x, max_x, min_z, max_z := points[0].x, points[0].x, points[0].z, points[0].z
    for point in points[1:] {min_x = min(min_x, point.x); max_x = max(max_x, point.x); min_z = min(min_z, point.z)
        max_z = max(max_z, point.z)}
    outer := request.width * .5 + max(request.feather, f32(0))
    authored := clamp(request.authored_level, 0, CLIPMAP_LEVELS - 1)
    data := &project.levels[authored]
    bx0, bz0, bx1, bz1, overlaps := level_sample_bounds(
        data,
        min_x - outer,
        min_z - outer,
        max_x + outer,
        max_z + outer,
    )
    if !overlaps do return false
    length := f32(0)
    for index in 0 ..< len(points) -
        1 { dx, dz := points[index + 1].x - points[index].x, points[index + 1].z - points[index].z; length += f32(math.sqrt(f64(dx * dx + dz * dz))) }
    if request.operation == .Grade && request.maximum_grade > 0 && abs(request.end_height - request.start_height) / max(length, f32(.001)) > request.maximum_grade do return false
    changed := false
    for z in bz0 ..= bz1 do for x in bx0 ..= bx1 {
        wx, wz := data.origin_x + f32(x) * data.cell_size, data.origin_z + f32(z) * data.cell_size
        if !authoring_level_is_finest_at(project, authored, wx, wz) do continue
        distance, signed, path_t, ok := authoring_closest_spline(points, wx, wz)
        if !ok || distance >= outer do continue
        mask := distance <= request.width * .5 ? f32(1) : 1 - (distance - request.width * .5) / max(request.feather, f32(.001))
        taper := request.endpoint_taper > 0 ? clamp(min(path_t, 1 - path_t) / request.endpoint_taper, f32(0), f32(1)) : f32(1)
        index := sample_index(x, z); current := data.heights[index]
        if !authoring_land_allowed(project, current, request.affect_seabed) do continue
        target := current
        profile_distance := clamp(distance / max(request.width * .5, f32(.001)), f32(0), f32(1))
        profile := request.profile == .Sharp ? 1 - profile_distance : request.profile == .Cliff ? (signed + request.side_bias * request.width >= 0 ? f32(1) : f32(0)) : f32(math.cos(f64(profile_distance) * math.PI * .5))
        switch request.operation {
        case .Ridge:
            target = current + request.height * profile * taper
        case .Valley:
            target = current - abs(request.height) * profile * taper
        case .Slope:
            target = current + request.height * clamp((signed / outer + 1) * .5 + request.side_bias, f32(0), f32(1)) * taper
        case .Grade:
            target = request.start_height + (request.end_height - request.start_height) * path_t
        }
        if request.roughness > 0 do target += authoring_noise(wx, wz, max(request.width * .2, f32(1)), 3, request.seed) * request.roughness * mask
        amount := mask * clamp(request.flow, f32(0), f32(1)) * taper
        next := current + (target - current) * amount
        if request.preserve_detail > 0 {
            next = current + (target - current) * amount * (1 - clamp(request.preserve_detail, f32(0), f32(1)))
        }
        if abs(next - current) > .00001 { data.heights[index] = next; changed = true }
    }
    if !changed do return false
    return true
}

apply_authoring_area :: proc(project: ^Project, request: Authoring_Area_Request) -> (bool, Authoring_Volume) {
    if project == nil do return false, {}
    if !request.single_level {
        changed := false
        volume: Authoring_Volume
        for level in 0 ..< CLIPMAP_LEVELS {
            level_request := request
            level_request.authored_level = level
            level_request.single_level = true
            level_changed, level_volume := apply_authoring_area(project, level_request)
            changed = level_changed || changed
            volume.cut += level_volume.cut
            volume.fill += level_volume.fill
        }
        if changed {
            start_x, start_z, start_ok := terrain_operator_source_point(
                project,
                request.owner,
                request.start_x,
                request.start_z,
            )
            end_x, end_z, end_ok := terrain_operator_source_point(project, request.owner, request.end_x, request.end_z)
            if start_ok && end_ok {
                feather := max(request.feather, f32(0))
                authoring_refresh_derived_bounds(
                    project,
                    min(start_x, end_x) - feather,
                    min(start_z, end_z) - feather,
                    max(start_x, end_x) + feather,
                    max(start_z, end_z) + feather,
                )
            }
            project.revision += 1
        }
        return changed, volume
    }
    start_x, start_z, start_ok := terrain_operator_source_point(
        project,
        request.owner,
        request.start_x,
        request.start_z,
    )
    end_x, end_z, end_ok := terrain_operator_source_point(project, request.owner, request.end_x, request.end_z)
    if !start_ok || !end_ok || request.flow <= 0 do return false, {}
    center_x, center_z := (start_x + end_x) * .5, (start_z + end_z) * .5
    half_x, half_z := abs(end_x - start_x) * .5, abs(end_z - start_z) * .5
    if half_x <= 0 || half_z <= 0 do return false, {}
    feather := max(request.feather, f32(0))
    authored := clamp(request.authored_level, 0, CLIPMAP_LEVELS - 1)
    data := &project.levels[authored]
    min_x, min_z, max_x, max_z, overlaps := level_sample_bounds(
        data,
        center_x - half_x - feather,
        center_z - half_z - feather,
        center_x + half_x + feather,
        center_z + half_z + feather,
    )
    if !overlaps do return false, {}
    corner := clamp(request.corner_radius, f32(0), min(half_x, half_z))
    volume: Authoring_Volume
    changed := false
    for z in min_z ..= max_z do for x in min_x ..= max_x {
        wx, wz := data.origin_x + f32(x) * data.cell_size, data.origin_z + f32(z) * data.cell_size
        if !authoring_level_is_finest_at(project, authored, wx, wz) do continue
        qx, qz := abs(wx - center_x) - (half_x - corner), abs(wz - center_z) - (half_z - corner)
        outside := f32(math.sqrt(f64(max(qx, f32(0)) * max(qx, f32(0)) + max(qz, f32(0)) * max(qz, f32(0))))) + min(max(qx, qz), f32(0)) - corner
        mask := outside <= 0 ? f32(1) : feather > 0 ? clamp(1 - outside / feather, f32(0), f32(1)) : f32(0)
        index := sample_index(x, z)
        current := data.heights[index]
        if mask <= 0 || !authoring_land_allowed(project, current, request.affect_seabed) do continue
        delta := request.target_height - current
        delta = delta < 0 ? max(delta, -max(request.cut_limit, f32(0))) : min(delta, max(request.fill_limit, f32(0)))
        applied := delta * mask * clamp(request.flow, f32(0), f32(1))
        if abs(applied) <= .00001 do continue
        data.heights[index] += applied
        sample_area := data.cell_size * data.cell_size
        if applied < 0 do volume.cut += -applied * sample_area
        if applied > 0 do volume.fill += applied * sample_area
        changed = true
    }
    if !changed do return false, {}
    return true, volume
}
