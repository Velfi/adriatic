package coastal_ecology

import "core:math"

GRID_X :: 88
GRID_Z :: 68
CELL_COUNT :: GRID_X * GRID_Z
MAX_ORGANISMS :: 720
MAX_WRACK :: 240

Species :: enum u8 {
    Barnacle,
    Mussel,
    Anemone,
    Limpet,
    Seaweed,
    Urchin,
    Starfish,
}

Habitat :: enum u8 {
    Subtidal,
    Reef,
    Rock_Platform,
    Tidepool,
    Pocket_Beach,
    Wrack_Shore,
    Backshore,
    Coastal_Scrub,
}

Config :: struct {
    seed:       u32,
    width:      f32,
    depth:      f32,
    relief:     f32,
    pool_depth: f32,
    tide_range: f32,
    biology:    f32,
    headlands:  f32,
    embayments: f32,
    platforms:  f32,
}

Cell :: struct {
    height:      f32,
    pool_floor:  f32,
    water_trap:  f32,
    crevice:     f32,
    wave_energy: f32,
    algae:       f32,
    sand:        f32,
    habitat:     Habitat,
}

Organism :: struct {
    species: Species,
    x, z:    f32,
    y:       f32,
    scale:   f32,
    yaw:     f32,
    wetness: f32,
    shelter: f32,
}

Wrack :: struct {
    x, y, z: f32,
    length:  f32,
    width:   f32,
    yaw:     f32,
    dry:     f32,
}

Plan :: struct {
    config:         Config,
    cells:          [CELL_COUNT]Cell,
    organisms:      [MAX_ORGANISMS]Organism,
    organism_count: int,
    wrack:          [MAX_WRACK]Wrack,
    wrack_count:    int,
    pool_cells:     int,
    habitat_counts: [len(Habitat)]int,
}

default_config :: proc() -> Config {
    return {
        seed = 0x54494445,
        width = 180,
        depth = 132,
        relief = 14,
        pool_depth = 2.4,
        tide_range = 4.2,
        biology = .46,
        headlands = .72,
        embayments = .68,
        platforms = .62,
    }
}

hash :: #force_inline proc(value: u32) -> u32 {
    result := value
    result = result ~ (result >> 16)
    result *= 0x7feb352d
    result = result ~ (result >> 15)
    result *= 0x846ca68b
    result = result ~ (result >> 16)
    return result
}

random01 :: #force_inline proc(value: u32) -> f32 {
    return f32(hash(value) & 0x00ffffff) / f32(0x01000000)
}

smooth :: #force_inline proc(value: f32) -> f32 {
    t := clamp(value, f32(0), f32(1))
    return t * t * (3 - 2 * t)
}

noise_lattice :: #force_inline proc(ix, iz: i32, seed: u32) -> f32 {
    h := hash(u32(ix) * 0x1f123bb5 ~ u32(iz) * 0x5f356495 ~ seed)
    return random01(h) * 2 - 1
}

noise :: proc(x, z: f32, seed: u32) -> f32 {
    ix, iz := i32(math.floor(x)), i32(math.floor(z))
    tx, tz := x - f32(ix), z - f32(iz)
    sx, sz := smooth(tx), smooth(tz)
    a := noise_lattice(ix, iz, seed) + (noise_lattice(ix + 1, iz, seed) - noise_lattice(ix, iz, seed)) * sx
    b := noise_lattice(ix, iz + 1, seed) + (noise_lattice(ix + 1, iz + 1, seed) - noise_lattice(ix, iz + 1, seed)) * sx
    return a + (b - a) * sz
}

cell_index :: #force_inline proc(x, z: int) -> int { return z * GRID_X + x }

generate :: proc(config: Config) -> Plan {
    result: Plan
    result.config = config
    for z in 0 ..< GRID_Z {
        nz := f32(z) / f32(GRID_Z - 1)
        for x in 0 ..< GRID_X {
            nx := f32(x) / f32(GRID_X - 1)
            coast_bend := noise(nx * 2.15, .37, config.seed ~ 0x2c1b3c6d) * .16 * config.embayments
            headland_wave := f32(math.sin(f64(nx * math.PI * 5 + random01(config.seed) * 4))) * .055 * config.headlands
            signed_shore := nz - (.47 + coast_bend + headland_wave)
            broad := noise(nx * 3.1, nz * 2.6, config.seed)
            joints := noise(nx * 10.5, nz * 8.7, config.seed ~ 0x91e10da5)
            fine := noise(nx * 24, nz * 20, config.seed ~ 0xa53c9e19)
            shore_rise := signed_shore * config.relief
            platform_signal := smooth(1 - math.abs(signed_shore) / max(.10 + config.platforms * .10, f32(.02)))
            shelf_source := shore_rise + broad * (1.1 + config.headlands)
            // Broad, weathered strata without quantizing the seabed. The old
            // floor() terrace made every contour read as a digital staircase.
            shelves := shelf_source + f32(math.sin(f64(shelf_source * 1.55))) * .16
            bowl_signal := noise(nx * 6.4 + 9, nz * 5.8 - 4, config.seed ~ 0x6c8e9cf5)
            basin := smooth((-bowl_signal - .12) * 1.85) * config.pool_depth * platform_signal
            crevice := smooth((math.abs(joints) - .54) * 2.8)
            height := shelves + broad * 1.15 + fine * .20 - basin
            trap := smooth(basin / max(config.pool_depth, f32(.01))) * (1 - crevice * .38)
            wave := clamp((1 - nz) * .72 + math.abs(fine) * .45, f32(0), f32(1))
            algae := clamp(trap * .72 + (1 - wave) * .25 + crevice * .18, f32(0), f32(1))
            pocket_signal := noise(nx * 4.4 + 13, nz * 3.1 - 7, config.seed ~ 0x7f4a7c15)
            sand := smooth((pocket_signal - .04) * 2.1) * smooth(1 - math.abs(signed_shore) / .16) * (1 - wave * .48)
            result.cells[cell_index(x, z)] = {
                height      = height,
                pool_floor  = height,
                water_trap  = trap,
                crevice     = crevice,
                wave_energy = wave,
                algae       = algae,
                sand        = sand,
            }
            if trap > .48 do result.pool_cells += 1
        }
    }

    // Erosion rounds the carved height field while leaving hydrology signals
    // intact. Three compact Gaussian-like passes are enough to remove grid
    // facets without washing away the pool basins that drive the ecology.
    smoothed: [CELL_COUNT]f32
    for _ in 0 ..< 3 {
        for z in 0 ..< GRID_Z {
            for x in 0 ..< GRID_X {
                index := cell_index(x, z)
                if x == 0 || z == 0 || x == GRID_X - 1 || z == GRID_Z - 1 {
                    smoothed[index] = result.cells[index].height
                    continue
                }
                center := result.cells[index].height * .40
                cardinal :=
                    (result.cells[cell_index(x - 1, z)].height +
                        result.cells[cell_index(x + 1, z)].height +
                        result.cells[cell_index(x, z - 1)].height +
                        result.cells[cell_index(x, z + 1)].height) *
                    .12
                diagonal :=
                    (result.cells[cell_index(x - 1, z - 1)].height +
                        result.cells[cell_index(x + 1, z - 1)].height +
                        result.cells[cell_index(x - 1, z + 1)].height +
                        result.cells[cell_index(x + 1, z + 1)].height) *
                    .03
                smoothed[index] = center + cardinal + diagonal
            }
        }
        for index in 0 ..< CELL_COUNT {
            result.cells[index].height = smoothed[index]
            result.cells[index].pool_floor = smoothed[index]
        }
    }

    // Classify broad habitat bands from coastal form, tidal elevation, and
    // substrate. These fields are the primary output; individual organisms
    // are optional detail generated from them below.
    low_tide := tide_height(config, 0)
    high_tide := tide_height(config, .5)
    for index in 0 ..< CELL_COUNT {
        cell := &result.cells[index]
        habitat: Habitat
        if cell.height < low_tide - 1.4 {
            habitat = cell.wave_energy > .62 ? .Reef : .Subtidal
        } else if cell.height <= high_tide {
            if cell.water_trap > .54 {
                habitat = .Tidepool
            } else if cell.sand > .48 {
                habitat = .Pocket_Beach
            } else {
                habitat = .Rock_Platform
            }
        } else if cell.height <= high_tide + .55 {
            habitat = cell.sand > .34 ? .Wrack_Shore : .Rock_Platform
        } else if cell.height <= high_tide + 2.4 {
            habitat = .Backshore
        } else {
            habitat = .Coastal_Scrub
        }
        cell.habitat = habitat
        result.habitat_counts[int(habitat)] += 1
    }

    // Deposit a persistent wrack line near the spring high-water contour.
    // This is generated once: runtime tide animation never searches contours
    // or simulates drifting debris.
    spring_high := tide_height(config, .5)
    for z in 1 ..< GRID_Z - 1 {
        for x in 1 ..< GRID_X - 1 {
            if result.wrack_count >= MAX_WRACK do break
            index := cell_index(x, z)
            cell := result.cells[index]
            contour_distance := math.abs(cell.height - spring_high)
            if contour_distance > .34 || cell.wave_energy < .26 do continue
            // Concave, sheltered notches collect more material than exposed
            // shoulders, but some exposed strands make the line continuous.
            retention := clamp(.32 + cell.crevice * .46 + (1 - cell.wave_energy) * .30, f32(0), f32(1))
            h := hash(config.seed ~ u32(index) * 0x85ebca6b)
            if random01(h) > retention do continue
            slope_x := result.cells[cell_index(x + 1, z)].height - result.cells[cell_index(x - 1, z)].height
            slope_z := result.cells[cell_index(x, z + 1)].height - result.cells[cell_index(x, z - 1)].height
            // The contour tangent is perpendicular to the height gradient.
            yaw := f32(math.atan2(f64(slope_z), f64(-slope_x)))
            jitter_x := (random01(h ~ 0x27d4eb2f) - .5) * config.width / f32(GRID_X - 1)
            jitter_z := (random01(h ~ 0x165667b1) - .5) * config.depth / f32(GRID_Z - 1)
            result.wrack[result.wrack_count] = {
                x      = f32(x) / f32(GRID_X - 1) * config.width - config.width * .5 + jitter_x,
                y      = cell.height,
                z      = f32(z) / f32(GRID_Z - 1) * config.depth - config.depth * .5 + jitter_z,
                length = .65 + random01(h ~ 0xd3a2646c) * 1.7,
                width  = .10 + random01(h ~ 0xfd7046c5) * .18,
                yaw    = yaw + (random01(h ~ 0xb55a4f09) - .5) * .34,
                dry    = clamp(contour_distance / .34 + random01(h ~ 0x94d049bb) * .35, f32(0), f32(1)),
            }
            result.wrack_count += 1
        }
    }

    attempts := int(f32(MAX_ORGANISMS) * clamp(config.biology, f32(0), f32(1)))
    for attempt in 0 ..< attempts {
        h := hash(config.seed ~ u32(attempt) * 0x9e3779b9)
        gx := int(h % u32(GRID_X))
        gz := int((h >> 9) % u32(GRID_Z))
        cell := result.cells[cell_index(gx, gz)]
        roll := random01(h ~ 0x45d9f3b)
        wet := clamp(cell.water_trap * .74 + (1 - f32(gz) / f32(GRID_Z - 1)) * .38, f32(0), f32(1))
        shelter := clamp(cell.crevice * .72 + cell.water_trap * .34, f32(0), f32(1))
        species: Species
        suitability: f32
        if wet > .78 && shelter > .38 {
            species, suitability = roll < .28 ? .Urchin : (roll < .62 ? .Anemone : .Starfish), wet * shelter
        } else if wet > .55 {
            species, suitability = roll < .46 ? .Seaweed : (roll < .72 ? .Mussel : .Anemone), wet
        } else if cell.wave_energy > .52 {
            species, suitability = roll < .58 ? .Barnacle : .Mussel, cell.wave_energy * (1 - wet * .25)
        } else {
            species, suitability = roll < .66 ? .Limpet : .Barnacle, .42 + shelter * .45
        }
        if random01(h ~ 0xc2b2ae35) > suitability * config.biology do continue
        if result.organism_count >= MAX_ORGANISMS do break
        jitter_x := random01(h ~ 0x27d4eb2f) - .5
        jitter_z := random01(h ~ 0x165667b1) - .5
        result.organisms[result.organism_count] = {
            species = species,
            x       = (f32(gx) + jitter_x) / f32(GRID_X - 1) * config.width - config.width * .5,
            z       = (f32(gz) + jitter_z) / f32(GRID_Z - 1) * config.depth - config.depth * .5,
            y       = cell.height,
            scale   = .55 + random01(h ~ 0xd3a2646c) * .9,
            yaw     = random01(h ~ 0xfd7046c5) * math.PI * 2,
            wetness = wet,
            shelter = shelter,
        }
        result.organism_count += 1
    }
    return result
}

sample :: proc(plan: ^Plan, x, z: f32) -> Cell {
    u := clamp((x / plan.config.width + .5) * f32(GRID_X - 1), f32(0), f32(GRID_X - 1))
    v := clamp((z / plan.config.depth + .5) * f32(GRID_Z - 1), f32(0), f32(GRID_Z - 1))
    ix, iz := int(math.floor(u)), int(math.floor(v))
    nx, nz := min(ix + 1, GRID_X - 1), min(iz + 1, GRID_Z - 1)
    tx, tz := u - f32(ix), v - f32(iz)
    a, b := plan.cells[cell_index(ix, iz)], plan.cells[cell_index(nx, iz)]
    c, d := plan.cells[cell_index(ix, nz)], plan.cells[cell_index(nx, nz)]
    result: Cell
    result.height =
        (a.height + (b.height - a.height) * tx) +
        ((c.height + (d.height - c.height) * tx) - (a.height + (b.height - a.height) * tx)) * tz
    result.pool_floor = result.height
    result.water_trap =
        (a.water_trap + (b.water_trap - a.water_trap) * tx) +
        ((c.water_trap + (d.water_trap - c.water_trap) * tx) - (a.water_trap + (b.water_trap - a.water_trap) * tx)) *
            tz
    result.crevice =
        (a.crevice + (b.crevice - a.crevice) * tx) +
        ((c.crevice + (d.crevice - c.crevice) * tx) - (a.crevice + (b.crevice - a.crevice) * tx)) * tz
    result.wave_energy =
        (a.wave_energy + (b.wave_energy - a.wave_energy) * tx) +
        ((c.wave_energy + (d.wave_energy - c.wave_energy) * tx) -
                (a.wave_energy + (b.wave_energy - a.wave_energy) * tx)) *
            tz
    result.algae =
        (a.algae + (b.algae - a.algae) * tx) +
        ((c.algae + (d.algae - c.algae) * tx) - (a.algae + (b.algae - a.algae) * tx)) * tz
    result.sand =
        (a.sand + (b.sand - a.sand) * tx) +
        ((c.sand + (d.sand - c.sand) * tx) - (a.sand + (b.sand - a.sand) * tx)) * tz
    nearest_x := tx < .5 ? ix : nx
    nearest_z := tz < .5 ? iz : nz
    result.habitat = plan.cells[cell_index(nearest_x, nearest_z)].habitat
    return result
}

tide_height :: proc(config: Config, phase: f32) -> f32 {
    // phase 0 = low, .5 = high; the secondary harmonic gives a less mechanical flood/ebb.
    fundamental := (1 - f32(math.cos(f64(phase * math.PI * 2)))) * .5
    asymmetry := f32(math.sin(f64(phase * math.PI * 4))) * .08
    return -config.tide_range * .36 + (fundamental + asymmetry) * config.tide_range
}

water_level :: proc(cell: Cell, config: Config, phase: f32) -> (f32, bool) {
    ocean := tide_height(config, phase)
    if ocean > cell.height do return ocean, true
    retained_depth := cell.water_trap * config.pool_depth * .58
    if retained_depth > .12 do return cell.height + retained_depth, true
    return cell.height, false
}
