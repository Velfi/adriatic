package terrain

import "core:math"

Marine_Habitat_Cell :: struct {
    seagrass, macroalgae, coralligenous, disturbance: u8,
}

Marine_Habitat_Chunk :: struct {
    chunk_x, chunk_z:           i32,
    owner:                      Island_ID,
    revision:                   u64,
    source_bathymetry_revision: u64,
    cells:                      [dynamic]Marine_Habitat_Cell,
}

Marine_Habitat_Sample :: struct {
    seagrass, macroalgae, coralligenous, disturbance: f32,
}

Marine_Habitat_Kind :: enum u8 {
    Bare,
    Seagrass,
    Macroalgae,
    Coralligenous,
}

Marine_Habitat_Exclusion :: struct {
    center_x, center_z, radius: f32,
}

marine_habitat_smoothstep :: #force_inline proc(edge0, edge1, value: f32) -> f32 {
    t := clamp((value - edge0) / max(edge1 - edge0, f32(.0001)), f32(0), f32(1))
    return t * t * (3 - 2 * t)
}

marine_habitat_destroy :: proc(chunks: ^[dynamic]Marine_Habitat_Chunk) {
    if chunks == nil do return
    for &chunk in chunks^ do delete(chunk.cells)
    delete(chunks^)
    chunks^ = nil
}

marine_habitat_hash01 :: #force_inline proc(x, z: i32, seed: u32) -> f32 {
    value := u32(x) * 0x1f123bb5 ~ u32(z) * 0x5f356495 ~ seed
    value = (value ~ (value >> 16)) * 0x7feb352d
    value = (value ~ (value >> 15)) * 0x846ca68b
    return f32((value ~ (value >> 16)) & 0x00ff_ffff) / f32(0x0100_0000)
}

marine_habitat_suitability :: proc(
    depth, slope, material, exposure, variation, disturbance: f32,
) -> Marine_Habitat_Sample {
    if depth <= 0 || depth > 32 do return {disturbance = disturbance}
    sand := clamp(-material, 0, 1)
    rock := clamp(material, 0, 1)
    gentle := 1 - clamp(slope / .42, 0, 1)
    seagrass_depth := marine_habitat_smoothstep(0.7, 2.0, depth) * (1 - marine_habitat_smoothstep(8, 11, depth))
    algae_depth := marine_habitat_smoothstep(.5, 2, depth) * (1 - marine_habitat_smoothstep(15, 19, depth))
    coral_depth := marine_habitat_smoothstep(5, 8, depth) * (1 - marine_habitat_smoothstep(26, 31, depth))
    undisturbed := 1 - clamp(disturbance, 0, 1)
    return {
        seagrass = clamp(
            seagrass_depth *
            gentle *
            (.42 + sand * .58) *
            (1 - exposure * .58) *
            (.62 + variation * .38) *
            undisturbed,
            0,
            1,
        ),
        macroalgae = clamp(
            algae_depth * (.30 + rock * .70) * (.35 + exposure * .65) * (.58 + variation * .42) * undisturbed,
            0,
            1,
        ),
        coralligenous = clamp(
            coral_depth * (.18 + rock * .82) * clamp(slope / .18, 0, 1) * (.40 + variation * .60) * undisturbed,
            0,
            1,
        ),
        disturbance = clamp(disturbance, 0, 1),
    }
}

marine_habitat_rebuild_all :: proc(project: ^Project, exclusions: []Marine_Habitat_Exclusion = nil) {
    if project == nil do return
    marine_habitat_destroy(&project.marine_habitat_chunks)
    for &bed in project.bathymetry_chunks {
        if len(bed.heights) != BATHYMETRY_CHUNK_SAMPLES || len(bed.material) != BATHYMETRY_CHUNK_SAMPLES do continue
        habitat := Marine_Habitat_Chunk {
            chunk_x                    = bed.chunk_x,
            chunk_z                    = bed.chunk_z,
            owner                      = bed.owner,
            revision                   = 1,
            source_bathymetry_revision = bed.revision,
            cells                      = make([dynamic]Marine_Habitat_Cell, BATHYMETRY_CHUNK_SAMPLES),
        }
        origin_x := f32(bed.chunk_x) * BATHYMETRY_CHUNK_SIZE
        origin_z := f32(bed.chunk_z) * BATHYMETRY_CHUNK_SIZE
        cell_size := BATHYMETRY_CHUNK_SIZE / f32(BATHYMETRY_CHUNK_RESOLUTION - 1)
        translation_x, translation_z: f32
        if owner_index, owned := island_index(bed.owner); owned {
            transform := island_transform_at(project, owner_index)
            translation_x = transform.current_x - transform.source_x
            translation_z = transform.current_z - transform.source_z
        }
        local_exclusions: [1024]int
        local_exclusion_count := 0
        world_min_x, world_min_z := origin_x + translation_x, origin_z + translation_z
        world_max_x, world_max_z := world_min_x + BATHYMETRY_CHUNK_SIZE, world_min_z + BATHYMETRY_CHUNK_SIZE
        for exclusion, exclusion_index in exclusions {
            closest_x := clamp(exclusion.center_x, world_min_x, world_max_x)
            closest_z := clamp(exclusion.center_z, world_min_z, world_max_z)
            ox, oz := exclusion.center_x - closest_x, exclusion.center_z - closest_z
            if ox * ox + oz * oz > exclusion.radius * exclusion.radius do continue
            if local_exclusion_count < len(local_exclusions) {
                local_exclusions[local_exclusion_count] = exclusion_index
                local_exclusion_count += 1
            }
        }
        for z in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
            for x in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
                index := z * BATHYMETRY_CHUNK_RESOLUTION + x
                xl, xr := max(x - 1, 0), min(x + 1, BATHYMETRY_CHUNK_RESOLUTION - 1)
                zd, zu := max(z - 1, 0), min(z + 1, BATHYMETRY_CHUNK_RESOLUTION - 1)
                dx :=
                    (f32(bed.heights[z * BATHYMETRY_CHUNK_RESOLUTION + xr]) -
                        f32(bed.heights[z * BATHYMETRY_CHUNK_RESOLUTION + xl])) /
                    max(f32(xr - xl) * cell_size, .001)
                dz :=
                    (f32(bed.heights[zu * BATHYMETRY_CHUNK_RESOLUTION + x]) -
                        f32(bed.heights[zd * BATHYMETRY_CHUNK_RESOLUTION + x])) /
                    max(f32(zu - zd) * cell_size, .001)
                source_x, source_z := origin_x + f32(x) * cell_size, origin_z + f32(z) * cell_size
                world_x, world_z := source_x + translation_x, source_z + translation_z
                disturbance := f32(0)
                for exclusion_index in local_exclusions[:local_exclusion_count] {
                    exclusion := exclusions[exclusion_index]
                    ox, oz := world_x - exclusion.center_x, world_z - exclusion.center_z
                    if ox * ox + oz * oz <= exclusion.radius * exclusion.radius do disturbance = 1
                }
                sample := marine_habitat_suitability(
                    project.sea_level - f32(bed.heights[index]),
                    f32(math.sqrt(f64(dx * dx + dz * dz))),
                    f32(bed.material[index]) / 63,
                    marine_habitat_hash01(bed.chunk_x, bed.chunk_z, 0x4a91) * .75,
                    marine_habitat_hash01(
                        i32(math.floor(f64(source_x / 12))),
                        i32(math.floor(f64(source_z / 12))),
                        0x91e1,
                    ),
                    disturbance,
                )
                habitat.cells[index] = {
                    u8(math.round(f64(sample.seagrass * 255))),
                    u8(math.round(f64(sample.macroalgae * 255))),
                    u8(math.round(f64(sample.coralligenous * 255))),
                    u8(math.round(f64(sample.disturbance * 255))),
                }
            }
        }
        append(&project.marine_habitat_chunks, habitat)
    }
    terrain_sampling_lookup_rebuild(project)
}

marine_habitat_chunk_at_source :: proc(project: ^Project, owner: Island_ID, x, z: f32) -> ^Marine_Habitat_Chunk {
    if project == nil do return nil
    if len(project.marine_habitat_lookup) != len(project.marine_habitat_chunks) do terrain_sampling_lookup_rebuild(project)
    key := [3]i32 {
        i32(owner),
        i32(math.floor(f64(x / BATHYMETRY_CHUNK_SIZE))),
        i32(math.floor(f64(z / BATHYMETRY_CHUNK_SIZE))),
    }
    if index, found := project.marine_habitat_lookup[key]; found && index >= 0 && index < len(project.marine_habitat_chunks) do return &project.marine_habitat_chunks[index]
    return nil
}

sample_marine_habitat :: proc(project: ^Project, x, z: f32) -> (Marine_Habitat_Sample, bool) {
    if project == nil do return {}, false
    source_x, source_z := x, z
    chunk: ^Marine_Habitat_Chunk
    for _, index in project.island_transforms {
        transform := island_transform_at(project, index)
        sx, sz := x - (transform.current_x - transform.source_x), z - (transform.current_z - transform.source_z)
        if candidate := marine_habitat_chunk_at_source(project, island_id_from_index(index), sx, sz);
           candidate != nil {
            chunk, source_x, source_z = candidate, sx, sz
            break
        }
    }
    if chunk == nil do chunk = marine_habitat_chunk_at_source(project, .World, x, z)
    if chunk == nil || len(chunk.cells) != BATHYMETRY_CHUNK_SAMPLES do return {}, false
    bed := bathymetry_chunk_at_source(project, chunk.owner, source_x, source_z)
    if bed == nil || chunk.source_bathymetry_revision != bed.revision do return {}, false
    origin_x, origin_z := f32(chunk.chunk_x) * BATHYMETRY_CHUNK_SIZE, f32(chunk.chunk_z) * BATHYMETRY_CHUNK_SIZE
    cell_size := BATHYMETRY_CHUNK_SIZE / f32(BATHYMETRY_CHUNK_RESOLUTION - 1)
    gx, gz :=
        clamp((source_x - origin_x) / cell_size, 0, f32(BATHYMETRY_CHUNK_RESOLUTION - 1)),
        clamp((source_z - origin_z) / cell_size, 0, f32(BATHYMETRY_CHUNK_RESOLUTION - 1))
    x0, z0 := int(math.floor(f64(gx))), int(math.floor(f64(gz)))
    x1, z1 := min(x0 + 1, BATHYMETRY_CHUNK_RESOLUTION - 1), min(z0 + 1, BATHYMETRY_CHUNK_RESOLUTION - 1)
    tx, tz := gx - f32(x0), gz - f32(z0)
    indices := [4]int {
        z0 * BATHYMETRY_CHUNK_RESOLUTION + x0,
        z0 * BATHYMETRY_CHUNK_RESOLUTION + x1,
        z1 * BATHYMETRY_CHUNK_RESOLUTION + x0,
        z1 * BATHYMETRY_CHUNK_RESOLUTION + x1,
    }
    values: [4]Marine_Habitat_Sample
    for corner, index in indices {
        cell := chunk.cells[corner]
        values[index] = {
            f32(cell.seagrass) / 255,
            f32(cell.macroalgae) / 255,
            f32(cell.coralligenous) / 255,
            f32(cell.disturbance) / 255,
        }
    }
    lerp4 := proc(v: [4]f32, tx, tz: f32) -> f32 {return(
            (v[0] + (v[1] - v[0]) * tx) +
            ((v[2] + (v[3] - v[2]) * tx) - (v[0] + (v[1] - v[0]) * tx)) * tz \
        )}
    return {
            lerp4({values[0].seagrass, values[1].seagrass, values[2].seagrass, values[3].seagrass}, tx, tz),
            lerp4({values[0].macroalgae, values[1].macroalgae, values[2].macroalgae, values[3].macroalgae}, tx, tz),
            lerp4(
                {values[0].coralligenous, values[1].coralligenous, values[2].coralligenous, values[3].coralligenous},
                tx,
                tz,
            ),
            lerp4(
                {values[0].disturbance, values[1].disturbance, values[2].disturbance, values[3].disturbance},
                tx,
                tz,
            ),
        },
        true
}

marine_habitat_dominant :: proc(sample: Marine_Habitat_Sample) -> Marine_Habitat_Kind {
    if sample.seagrass >= sample.macroalgae && sample.seagrass >= sample.coralligenous && sample.seagrass > .12 do return .Seagrass
    if sample.macroalgae >= sample.coralligenous && sample.macroalgae > .12 do return .Macroalgae
    if sample.coralligenous > .12 do return .Coralligenous
    return .Bare
}

marine_habitat_paint :: proc(
    project: ^Project,
    world_x, world_z, radius, strength, hardness: f32,
    kind: Marine_Habitat_Kind,
    erase: bool = false,
) -> bool {
    if project == nil || radius <= 0 || strength <= 0 do return false
    changed := false
    exponent := 1 + (1 - clamp(hardness, f32(0), f32(1))) * 3
    cell_size := BATHYMETRY_CHUNK_SIZE / f32(BATHYMETRY_CHUNK_RESOLUTION - 1)
    for &chunk in project.marine_habitat_chunks {
        if len(chunk.cells) != BATHYMETRY_CHUNK_SAMPLES do continue
        translation_x, translation_z: f32
        if owner_index, owned := island_index(chunk.owner); owned {
            transform := island_transform_at(project, owner_index)
            translation_x = transform.current_x - transform.source_x
            translation_z = transform.current_z - transform.source_z
        }
        origin_x := f32(chunk.chunk_x) * BATHYMETRY_CHUNK_SIZE + translation_x
        origin_z := f32(chunk.chunk_z) * BATHYMETRY_CHUNK_SIZE + translation_z
        closest_x := clamp(world_x, origin_x, origin_x + BATHYMETRY_CHUNK_SIZE)
        closest_z := clamp(world_z, origin_z, origin_z + BATHYMETRY_CHUNK_SIZE)
        ox, oz := world_x - closest_x, world_z - closest_z
        if ox * ox + oz * oz > radius * radius do continue
        chunk_changed := false
        for z in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
            sample_z := origin_z + f32(z) * cell_size
            for x in 0 ..< BATHYMETRY_CHUNK_RESOLUTION {
                sample_x := origin_x + f32(x) * cell_size
                dx, dz := sample_x - world_x, sample_z - world_z
                distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
                if distance > radius do continue
                falloff := f32(math.pow(f64(1 - distance / radius), f64(exponent)))
                delta := int(math.round(f64(strength * falloff * 255)))
                if delta <= 0 do continue
                cell := &chunk.cells[z * BATHYMETRY_CHUNK_RESOLUTION + x]
                before := cell^
                if kind == .Bare {
                    signed := erase ? -delta : delta
                    cell.disturbance = u8(clamp(int(cell.disturbance) + signed, 0, 255))
                    if !erase {
                        cell.seagrass = u8(max(int(cell.seagrass) - delta, 0))
                        cell.macroalgae = u8(max(int(cell.macroalgae) - delta, 0))
                        cell.coralligenous = u8(max(int(cell.coralligenous) - delta, 0))
                    }
                } else {
                    target: ^u8
                    switch kind {
                    case .Seagrass:
                        target = &cell.seagrass
                    case .Macroalgae:
                        target = &cell.macroalgae
                    case .Coralligenous:
                        target = &cell.coralligenous
                    case .Bare:
                    }
                    if target != nil {
                        signed := erase ? -delta : delta
                        target^ = u8(clamp(int(target^) + signed, 0, 255))
                        if !erase do cell.disturbance = u8(max(int(cell.disturbance) - delta, 0))
                    }
                }
                if cell^ != before do chunk_changed = true
            }
        }
        if chunk_changed {
            chunk.revision += 1
            changed = true
        }
    }
    if changed do project.revision += 1
    return changed
}
