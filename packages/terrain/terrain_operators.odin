package terrain

import "core:math"

Terrain_Operator_Area :: struct {
    owner:              Island_ID,
    start_x, start_z:   f32,
    end_x, end_z:       f32,
    target_height:      f32,
    boundary_blend:     f32,
}

terrain_operator_source_point :: proc(project: ^Project, owner: Island_ID, world_x, world_z: f32) -> (f32, f32, bool) {
    if project == nil || owner == .World || island_at(project, world_x, world_z) != owner do return 0, 0, false
    index, ok := island_index(owner)
    if !ok do return 0, 0, false
    transform := island_transform_at(project, index)
    return world_x - (transform.current_x - transform.source_x),
        world_z - (transform.current_z - transform.source_z), true
}

terrain_operator_authored_level :: proc(project: ^Project, min_x, min_z, max_x, max_z: f32) -> int {
    for level in 0 ..< CLIPMAP_LEVELS {
        if level_contains_bounds(&project.levels[level], min_x, min_z, max_x, max_z) do return level
    }
    return CLIPMAP_LEVELS - 1
}

terrain_operator_falloff :: #force_inline proc(distance, radius, hardness: f32) -> f32 {
    if distance >= radius do return 0
    exponent := 1 + (1 - clamp(hardness, f32(0), f32(1))) * 2
    return f32(math.pow(f64(1 - distance / radius), f64(exponent)))
}

terrain_operator_propagate :: proc(project: ^Project, authored_level: int, center_x, center_z, radius: f32) {
    source := &project.levels[authored_level]
    for level in 0 ..< authored_level {
        finer := &project.levels[level]
        min_x, min_z, max_x, max_z, overlaps := level_sample_bounds(
            finer, center_x - radius, center_z - radius, center_x + radius, center_z + radius,
        )
        if !overlaps do continue
        for z in min_z ..= max_z {
            sample_z := finer.origin_z + f32(z) * finer.cell_size
            for x in min_x ..= max_x {
                sample_x := finer.origin_x + f32(x) * finer.cell_size
                if !level_contains(source, sample_x, sample_z) do continue
                index := sample_index(x, z)
                finer.heights[index] = sample_level_height(source, sample_x, sample_z)
                finer.material[index] = sample_level_material(source, sample_x, sample_z)
            }
        }
    }
    for level in authored_level + 1 ..< CLIPMAP_LEVELS {
        finer := &project.levels[level - 1]
        coarse := &project.levels[level]
        min_x, min_z, max_x, max_z, overlaps := level_sample_bounds(
            coarse, center_x - radius, center_z - radius, center_x + radius, center_z + radius,
        )
        if !overlaps do continue
        for z in min_z ..= max_z {
            sample_z := coarse.origin_z + f32(z) * coarse.cell_size
            for x in min_x ..= max_x {
                sample_x := coarse.origin_x + f32(x) * coarse.cell_size
                if !level_contains(finer, sample_x, sample_z) do continue
                index := sample_index(x, z)
                coarse.heights[index] = sample_level_height(finer, sample_x, sample_z)
                coarse.material[index] = sample_level_material(finer, sample_x, sample_z)
            }
        }
    }
}

apply_level_operator :: proc(
    project: ^Project, owner: Island_ID, world_x, world_z, radius, target, amount, hardness: f32,
) -> bool {
    source_x, source_z, valid := terrain_operator_source_point(project, owner, world_x, world_z)
    if !valid || radius <= 0 || amount <= 0 do return false
    authored := terrain_operator_authored_level(project, source_x - radius, source_z - radius, source_x + radius, source_z + radius)
    data := &project.levels[authored]
    effective_radius := max(radius, data.cell_size * 1.5)
    min_x, min_z, max_x, max_z, overlaps := level_sample_bounds(
        data, source_x - effective_radius, source_z - effective_radius, source_x + effective_radius, source_z + effective_radius,
    )
    if !overlaps do return false
    changed := false
    for z in min_z ..= max_z {
        sample_z := data.origin_z + f32(z) * data.cell_size
        for x in min_x ..= max_x {
            sample_x := data.origin_x + f32(x) * data.cell_size
            dx, dz := sample_x - source_x, sample_z - source_z
            distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
            weight := terrain_operator_falloff(distance, effective_radius, hardness) * clamp(amount, f32(0), f32(1))
            index := sample_index(x, z)
            if weight <= 0 || data.heights[index] <= project.sea_level + SHORELINE_EPSILON do continue
            data.heights[index] += (target - data.heights[index]) * weight
            changed = true
        }
    }
    if !changed do return false
    terrain_operator_propagate(project, authored, source_x, source_z, effective_radius + data.cell_size * 2)
    project.revision += 1
    return true
}

apply_level_area_operator :: proc(project: ^Project, area: Terrain_Operator_Area, amount, hardness: f32) -> bool {
    start_x, start_z, start_ok := terrain_operator_source_point(project, area.owner, area.start_x, area.start_z)
    end_x, end_z, end_ok := terrain_operator_source_point(project, area.owner, area.end_x, area.end_z)
    if !start_ok || !end_ok || amount <= 0 do return false
    min_world_x, max_world_x := min(start_x, end_x), max(start_x, end_x)
    min_world_z, max_world_z := min(start_z, end_z), max(start_z, end_z)
    blend := max(area.boundary_blend * (1 - clamp(hardness, f32(0), f32(1))), f32(0))
    authored := terrain_operator_authored_level(
        project, min_world_x - blend, min_world_z - blend, max_world_x + blend, max_world_z + blend,
    )
    data := &project.levels[authored]
    min_x, min_z, max_x, max_z, overlaps := level_sample_bounds(
        data, min_world_x - blend, min_world_z - blend, max_world_x + blend, max_world_z + blend,
    )
    if !overlaps do return false
    changed := false
    for z in min_z ..= max_z {
        sample_z := data.origin_z + f32(z) * data.cell_size
        for x in min_x ..= max_x {
            sample_x := data.origin_x + f32(x) * data.cell_size
            outside_x := max(max(min_world_x - sample_x, f32(0)), sample_x - max_world_x)
            outside_z := max(max(min_world_z - sample_z, f32(0)), sample_z - max_world_z)
            outside := f32(math.sqrt(f64(outside_x * outside_x + outside_z * outside_z)))
            weight := outside <= 0 ? f32(1) : blend > 0 ? clamp(1 - outside / blend, f32(0), f32(1)) : 0
            index := sample_index(x, z)
            if weight <= 0 || data.heights[index] <= project.sea_level + SHORELINE_EPSILON do continue
            data.heights[index] += (area.target_height - data.heights[index]) * weight * clamp(amount, f32(0), f32(1))
            changed = true
        }
    }
    if !changed do return false
    center_x, center_z := (min_world_x + max_world_x) * .5, (min_world_z + max_world_z) * .5
    dx, dz := max_world_x - min_world_x + blend * 2, max_world_z - min_world_z + blend * 2
    radius := f32(math.sqrt(f64(dx * dx + dz * dz))) * .5 + data.cell_size * 2
    terrain_operator_propagate(project, authored, center_x, center_z, radius)
    project.revision += 1
    return true
}

apply_grade_operator :: proc(
    project: ^Project, owner: Island_ID,
    start_world_x, start_world_z, start_height, end_world_x, end_world_z, end_height,
    width, side_blend, amount: f32,
) -> bool {
    start_x, start_z, start_ok := terrain_operator_source_point(project, owner, start_world_x, start_world_z)
    end_x, end_z, end_ok := terrain_operator_source_point(project, owner, end_world_x, end_world_z)
    if !start_ok || !end_ok || width <= 0 || amount <= 0 do return false
    dx, dz := end_x - start_x, end_z - start_z
    length_squared := dx * dx + dz * dz
    if length_squared <= .0001 do return false
    outer := width * .5 + max(side_blend, f32(0))
    bounds_min_x, bounds_max_x := min(start_x, end_x) - outer, max(start_x, end_x) + outer
    bounds_min_z, bounds_max_z := min(start_z, end_z) - outer, max(start_z, end_z) + outer
    authored := terrain_operator_authored_level(project, bounds_min_x, bounds_min_z, bounds_max_x, bounds_max_z)
    data := &project.levels[authored]
    min_x, min_z, max_x, max_z, overlaps := level_sample_bounds(data, bounds_min_x, bounds_min_z, bounds_max_x, bounds_max_z)
    if !overlaps do return false
    changed := false
    for z in min_z ..= max_z {
        sample_z := data.origin_z + f32(z) * data.cell_size
        for x in min_x ..= max_x {
            sample_x := data.origin_x + f32(x) * data.cell_size
            t := clamp(((sample_x - start_x) * dx + (sample_z - start_z) * dz) / length_squared, f32(0), f32(1))
            offset_x := sample_x - (start_x + dx * t)
            offset_z := sample_z - (start_z + dz * t)
            distance := f32(math.sqrt(f64(offset_x * offset_x + offset_z * offset_z)))
            if distance >= outer do continue
            weight := distance <= width * .5 ? f32(1) : 1 - (distance - width * .5) / max(side_blend, f32(.001))
            index := sample_index(x, z)
            if data.heights[index] <= project.sea_level + SHORELINE_EPSILON do continue
            target := start_height + (end_height - start_height) * t
            data.heights[index] += (target - data.heights[index]) * weight * clamp(amount, f32(0), f32(1))
            changed = true
        }
    }
    if !changed do return false
    center_x, center_z := (start_x + end_x) * .5, (start_z + end_z) * .5
    radius := f32(math.sqrt(f64(length_squared))) * .5 + outer + data.cell_size * 2
    terrain_operator_propagate(project, authored, center_x, center_z, radius)
    project.revision += 1
    return true
}

apply_terrace_operator :: proc(
    project: ^Project, owner: Island_ID, world_x, world_z, radius, interval, offset, amount, hardness: f32,
) -> bool {
    source_x, source_z, valid := terrain_operator_source_point(project, owner, world_x, world_z)
    if !valid || radius <= 0 || interval <= 0 || amount <= 0 do return false
    authored := terrain_operator_authored_level(project, source_x - radius, source_z - radius, source_x + radius, source_z + radius)
    data := &project.levels[authored]
    effective_radius := max(radius, data.cell_size * 1.5)
    min_x, min_z, max_x, max_z, overlaps := level_sample_bounds(data, source_x - effective_radius, source_z - effective_radius, source_x + effective_radius, source_z + effective_radius)
    if !overlaps do return false
    changed := false
    for z in min_z ..= max_z {
        sample_z := data.origin_z + f32(z) * data.cell_size
        for x in min_x ..= max_x {
            sample_x := data.origin_x + f32(x) * data.cell_size
            dx, dz := sample_x - source_x, sample_z - source_z
            distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
            weight := terrain_operator_falloff(distance, effective_radius, hardness) * clamp(amount, f32(0), f32(1))
            index := sample_index(x, z)
            if weight <= 0 || data.heights[index] <= project.sea_level + SHORELINE_EPSILON do continue
            stepped := offset + f32(math.round(f64((data.heights[index] - offset) / interval))) * interval
            data.heights[index] += (stepped - data.heights[index]) * weight
            changed = true
        }
    }
    if !changed do return false
    terrain_operator_propagate(project, authored, source_x, source_z, effective_radius + data.cell_size * 2)
    project.revision += 1
    return true
}

apply_erode_operator :: proc(
    project: ^Project, owner: Island_ID, world_x, world_z, radius, talus, amount, hardness: f32,
) -> bool {
    source_x, source_z, valid := terrain_operator_source_point(project, owner, world_x, world_z)
    if !valid || radius <= 0 || amount <= 0 do return false
    authored := terrain_operator_authored_level(project, source_x - radius, source_z - radius, source_x + radius, source_z + radius)
    data := &project.levels[authored]
    effective_radius := max(radius, data.cell_size * 1.5)
    min_x, min_z, max_x, max_z, overlaps := level_sample_bounds(data, source_x - effective_radius, source_z - effective_radius, source_x + effective_radius, source_z + effective_radius)
    if !overlaps do return false
    width, height := max_x - min_x + 1, max_z - min_z + 1
    source := make([]f32, width * height)
    defer delete(source)
    for z in min_z ..= max_z do for x in min_x ..= max_x {
        source[(z - min_z) * width + x - min_x] = data.heights[sample_index(x, z)]
    }
    changed := false
    for z in min_z ..= max_z {
        sample_z := data.origin_z + f32(z) * data.cell_size
        for x in min_x ..= max_x {
            sample_x := data.origin_x + f32(x) * data.cell_size
            dx, dz := sample_x - source_x, sample_z - source_z
            distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
            weight := terrain_operator_falloff(distance, effective_radius, hardness) * clamp(amount, f32(0), f32(1))
            local := (z - min_z) * width + x - min_x
            center := source[local]
            if weight <= 0 || center <= project.sea_level + SHORELINE_EPSILON do continue
            left := source[(z - min_z) * width + clamp(x - 1, min_x, max_x) - min_x]
            right := source[(z - min_z) * width + clamp(x + 1, min_x, max_x) - min_x]
            up := source[(clamp(z - 1, min_z, max_z) - min_z) * width + x - min_x]
            down := source[(clamp(z + 1, min_z, max_z) - min_z) * width + x - min_x]
            average := (left + right + up + down) * .25
            if abs(center - average) <= max(talus, f32(0)) do continue
            data.heights[sample_index(x, z)] += (average - center) * weight
            changed = true
        }
    }
    if !changed do return false
    terrain_operator_propagate(project, authored, source_x, source_z, effective_radius + data.cell_size * 2)
    project.revision += 1
    return true
}
