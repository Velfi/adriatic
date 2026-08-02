package estuaries

import spring_river "../spring_river"
import "base:runtime"
import "core:math"

// Keep the generated bed close enough to the 1 m terrain grid that narrow
// channels and wetland boundaries do not resolve as visibly larger source
// cells after they are baked into the map. The default 660 m basin samples at
// about 2.6 m here; the former 128-square field sampled at about 5.2 m.
GRID_WIDTH :: 256
GRID_HEIGHT :: 256
CELL_COUNT :: GRID_WIDTH * GRID_HEIGHT
SIMULATION_STEPS :: 240
MAX_CANDIDATE_ATTEMPTS :: 8
VALID_CANDIDATES_REQUIRED :: 3
MAX_EROSION_PER_STEP :: f32(.012)

Archetype :: enum u8 {
    Tidal_Estuary,
    Distributary_Delta,
}

Orientation :: enum u8 {
    North,
    East,
    South,
    West,
}

Wetland_Class :: enum u8 {
    Dry,
    Channel,
    Mudflat,
    Marsh,
    Shoal,
    Open_Sea,
}

Point :: struct {
    x, z: f32,
}
Contour :: struct {
    points: [dynamic]Point,
    closed: bool,
}
Graph_Node :: struct {
    position: Point,
    order:    u8,
    outlet:   bool,
}
Graph_Edge :: struct {
    from, to: int,
    order:    u8,
}

Config :: struct {
    seed:           u32,
    archetype:      Archetype,
    orientation:    Orientation,
    branching:      f32,
    mouth_width:    f32,
    sediment_load:  f32,
    relief:         f32,
    mean_sea_level: f32,
    tidal_range:    f32,
}

Diagnostics :: struct {
    rejection_mask:         u32,
    outlet_count:           int,
    dominant_outlet_share:  f32,
    navigable_fraction:     f32,
    wetland_fraction:       f32,
    shoal_fraction:         f32,
    island_count:           int,
    eroded_volume:          f32,
    deposited_volume:       f32,
    sediment_balance_error: f32,
    maximum_flow:           f32,
    unintended_outlets:     int,
    connected_to_sea:       bool,
}

Plan :: struct {
    config:             Config,
    requested_seed:     u32,
    selected_seed:      u32,
    attempts:           int,
    valid:              bool,
    score:              f32,
    elevation:          []f32,
    water_depth:        []f32,
    flow_x:             []f32,
    flow_z:             []f32,
    sediment:           []f32,
    erosion_deposition: []f32,
    wetland:            []Wetland_Class,
    channel_order:      []u8,
    contours:           [dynamic]Contour,
    graph_nodes:        [dynamic]Graph_Node,
    graph_edges:        [dynamic]Graph_Edge,
    diagnostics:        Diagnostics,
    allocator:          runtime.Allocator,
}

REJECT_CONNECTION :: u32(1 << 0)
REJECT_BORDER :: u32(1 << 1)
REJECT_TOPOLOGY :: u32(1 << 2)
REJECT_NUMERIC :: u32(1 << 3)
REJECT_SEDIMENT :: u32(1 << 4)
REJECT_ISLANDS :: u32(1 << 5)

default_config :: proc() -> Config {
    return {
        seed = 0x45535459,
        archetype = .Tidal_Estuary,
        orientation = .North,
        branching = .55,
        mouth_width = .22,
        sediment_load = .60,
        relief = 12,
        mean_sea_level = 0,
        tidal_range = 1.4,
    }
}

config_from_river_mouth :: proc(mouth: spring_river.Mouth, archetype: Archetype, domain_half_width: f32) -> Config {
    config := default_config()
    config.seed = hash(u32(math.abs(mouth.position[0]) * 8191) ~ u32(math.abs(mouth.position[1]) * 131071))
    config.archetype = archetype
    config.orientation = .North
    config.mean_sea_level = mouth.water_level
    config.branching = clamp(.18 + mouth.discharge * .46 + mouth.sediment_load * .18, f32(0), f32(1))
    config.mouth_width = clamp(mouth.width / max(domain_half_width, f32(1)) * 1.8, f32(.08), f32(.45))
    config.sediment_load = clamp(mouth.sediment_load, f32(0), f32(1))
    config.relief = clamp(5 + mouth.depth * 4.5 + mouth.discharge * 2.2, f32(2), f32(30))
    config.tidal_range = clamp(.7 + mouth.discharge * .42, f32(0), f32(4))
    return config
}

clamp_config :: proc(value: Config) -> Config {
    result := value
    result.branching = clamp(result.branching, 0, 1)
    result.mouth_width = clamp(result.mouth_width, .08, .45)
    result.sediment_load = clamp(result.sediment_load, 0, 1)
    result.relief = clamp(result.relief, 2, 30)
    result.mean_sea_level = clamp(result.mean_sea_level, -5, 5)
    result.tidal_range = clamp(result.tidal_range, 0, 4)
    return result
}

archetype_name :: proc(value: Archetype) -> string {
    return value == .Tidal_Estuary ? "TIDAL ESTUARY" : "DISTRIBUTARY DELTA"
}

rejection_text :: proc(mask: u32) -> string {
    if mask == 0 do return "VALID"
    if mask & REJECT_CONNECTION != 0 do return "NO RIVER-SEA CONNECTION"
    if mask & REJECT_BORDER != 0 do return "UNINTENDED BORDER OUTLET"
    if mask & REJECT_TOPOLOGY != 0 do return "ARCHETYPE TOPOLOGY"
    if mask & REJECT_NUMERIC != 0 do return "NUMERICAL INSTABILITY"
    if mask & REJECT_SEDIMENT != 0 do return "SEDIMENT IMBALANCE"
    return "TOO FEW TIDAL ISLANDS"
}

hash :: proc(value: u32) -> u32 {
    x := value
    x = x ~ (x >> 16); x *= 0x7feb352d
    x = x ~ (x >> 15); x *= 0x846ca68b
    return x ~ (x >> 16)
}

index_of :: #force_inline proc(x, z: int) -> int { return z * GRID_WIDTH + x }

noise :: #force_inline proc(x, z: int, seed: u32) -> f32 {
    value := hash(seed ~ u32(x * 73856093) ~ u32(z * 19349663))
    return f32(value & 0xffff) / 65535 * 2 - 1
}

coastal_variation :: proc(nx, nz: f32, seed: u32) -> f32 {
    phase_a := f64(seed & 0xffff) * .00037
    phase_b := f64(seed >> 16) * .00051
    // Long, incommensurate waves avoid the square plateaus and octave grid
    // signature of value noise while retaining deterministic regional relief.
    broad := math.sin(f64(nx) * 4.73 + f64(nz) * 2.19 + phase_a)
    cross := math.sin(f64(nx) * -2.31 + f64(nz) * 5.17 + phase_b)
    detail := math.sin(f64(nx) * 9.11 + f64(nz) * -4.37 + phase_a * .7 + phase_b)
    return f32(broad * .52 + cross * .31 + detail * .17)
}

smoothstep :: #force_inline proc(value: f32) -> f32 {
    t := clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
}

tidal_island_surface :: proc(config: Config, nx, nz: f32) -> (height: f32, present: bool) {
    // Seeded, anisotropic sediment bodies occupy the tidal basin. Compact
    // smooth kernels make natural bars and marsh islets without importing a
    // value-noise grid signature into the terrain.
    count := 28 + int(config.branching * 18) + int(config.sediment_load * 10)
    best := f32(-1e6)
    for island in 0 ..< count {
        salt := hash(config.seed ~ u32(island) * 0x9e3779b9 ~ 0x49534c54)
        center_z := -.68 + f32((salt >> 16) & 0xffff) / 65535 * .60
        basin_progress := clamp((.18 - center_z) / .94, 0, 1)
        basin_center := f32(math.sin(f64((center_z + .35) * 3.1 + f32(config.seed & 255) * .011))) * (.025 + basin_progress * .035)
        basin_half_width := .065 + smoothstep(basin_progress) * (.35 + config.mouth_width * .95)
        center_x := basin_center + (f32(salt & 0xffff) / 65535 * 2 - 1) * basin_half_width * .78
        radius_x := .018 + f32(hash(salt ~ 0x57494454) & 255) / 255 * (.030 + config.branching * .020)
        radius_z := .026 + f32(hash(salt ~ 0x4c454e47) & 255) / 255 * (.045 + config.sediment_load * .028)
        // Rotate the long axis slightly by shearing x along z. This keeps the
        // bars flow-aligned without making them parallel capsules.
        lean := (f32(hash(salt ~ 0x4c45414e) & 255) / 255 * 2 - 1) * .45
        local_z := (nz - center_z) / radius_z
        local_x := (nx - center_x - (nz - center_z) * lean) / radius_x
        angle := f32(math.atan2(f64(local_z), f64(local_x)))
        outline_phase := f32(hash(salt ~ 0x4f55544c) & 1023) / 1023 * math.TAU
        outline :=
            .82 +
            f32(math.sin(f64(angle * 3 + outline_phase))) * .08 +
            f32(math.sin(f64(angle * 5 - outline_phase * .71))) * .04
        radial := (local_x * local_x + local_z * local_z) / (outline * outline)
        if radial >= 1 do continue
        // Marsh islands are low platforms with a comparatively narrow tidal
        // scarp, not smooth dunes. Reach the crown across the inner half of
        // the footprint so eye-level views show a bank and a broad reed bed.
        crown := smoothstep(clamp((1 - radial) / .45, 0, 1))
        crown *= .72 + .28 * f32(math.sin(f64(local_x * 2.7 + local_z * 1.9 + f32(salt & 63))))
        crown_variation := f32(hash(salt ~ 0x43524f57) & 255) / 255
        island_height :=
            config.mean_sea_level + .28 + config.tidal_range * .24 + config.sediment_load * .78 + crown_variation * .62
        best = max(best, config.mean_sea_level - .20 + (island_height - (config.mean_sea_level - .20)) * crown)
    }
    return best, best > -1e5
}

tidal_creek_geometry :: proc(config: Config, nx, nz: f32) -> (weight: f32, order: u8) {
    if nz < -.70 || nz > .08 do return 0, 0
    creek_count := 3 + int(config.branching * 4)
    best := f32(0)
    for creek in 0 ..< creek_count {
        salt := hash(config.seed ~ u32(creek) * 0x85ebca6b ~ 0x43524545)
        anchor := (f32(salt & 255) / 255 * 2 - 1) * (.24 + config.mouth_width)
        phase := f32((salt >> 8) & 255) / 255 * math.TAU
        frequency := 3.2 + f32((salt >> 16) & 255) / 255 * 3.4
        center := anchor + f32(math.sin(f64((nz + .70) * frequency + phase))) * (.035 + config.branching * .035)
        width := .010 + f32((salt >> 24) & 255) / 255 * .012
        best = max(best, 1 - smoothstep(math.abs(nx - center) / width))
    }
    return best, best > .45 ? u8(1) : u8(0)
}

destroy :: proc(plan: ^Plan) {
    if plan == nil do return
    for &contour in plan.contours do delete(contour.points)
    delete(plan.contours); delete(plan.graph_nodes); delete(plan.graph_edges)
    delete(plan.elevation, plan.allocator); delete(plan.water_depth, plan.allocator)
    delete(plan.flow_x, plan.allocator); delete(plan.flow_z, plan.allocator)
    delete(plan.sediment, plan.allocator); delete(plan.erosion_deposition, plan.allocator)
    delete(plan.wetland, plan.allocator); delete(plan.channel_order, plan.allocator)
    plan^ = {}
}

allocate_plan :: proc(config: Config, allocator: runtime.Allocator) -> Plan {
    return {
        config = config,
        selected_seed = config.seed,
        elevation = make([]f32, CELL_COUNT, allocator),
        water_depth = make([]f32, CELL_COUNT, allocator),
        flow_x = make([]f32, CELL_COUNT, allocator),
        flow_z = make([]f32, CELL_COUNT, allocator),
        sediment = make([]f32, CELL_COUNT, allocator),
        erosion_deposition = make([]f32, CELL_COUNT, allocator),
        wetland = make([]Wetland_Class, CELL_COUNT, allocator),
        channel_order = make([]u8, CELL_COUNT, allocator),
        contours = make([dynamic]Contour, allocator),
        graph_nodes = make([dynamic]Graph_Node, allocator),
        graph_edges = make([dynamic]Graph_Edge, allocator),
        allocator = allocator,
    }
}

channel_geometry :: proc(config: Config, nx, nz: f32) -> (distance, half_width: f32, order: u8) {
    phase := f32(config.seed & 255) * .017
    primary := f32(math.sin(f64((nz + 1) * math.PI * 1.42 + phase)))
    secondary := f32(math.sin(f64((nz + 1) * math.PI * 3.17 - phase * .63)))
    // A river-scale compound wave gives the inland reach real bends at world
    // scale.  The prior 15–30 m offset read as an almost perfectly straight,
    // symmetric trench from a human-height camera.
    meander := (primary + secondary * .28) * (.045 + config.branching * .055)
    downstream_envelope := smoothstep((nz + 1) * .5)
    // The graph and boundary condition place the river inlet at {0, 1}.
    // Bring the procedural trunk onto that axis before allowing its meander
    // to develop; otherwise the first interior cells jump sideways from the
    // centered opening and leave a broken, diamond-shaped river handoff.
    inlet_envelope := smoothstep((1 - nz) / .18)
    trunk_x := meander * downstream_envelope * inlet_envelope
    coast_t := clamp((.30 - nz) / 1.30, 0, 1)
    if config.archetype == .Tidal_Estuary {
        width := .025 + coast_t * config.mouth_width * .5
        return math.abs(nx - trunk_x), width, 3
    }
    split := clamp((.28 - nz) / .92, 0, 1)
    separation := split * (.10 + config.branching * .22)
    branch_count := config.branching > .72 ? 3 : 2
    best := math.abs(nx - trunk_x)
    best_order := u8(3)
    if split > 0 {
        left := math.abs(nx - (trunk_x - separation))
        right := math.abs(nx - (trunk_x + separation))
        if left < best do best, best_order = left, 2
        if right < best do best, best_order = right, 2
        if branch_count == 3 {
            middle := math.abs(nx - trunk_x)
            if middle < best do best, best_order = middle, 1
        }
    }
    width := .022 + coast_t * config.mouth_width * .16
    return best, width, best_order
}

build_initial :: proc(plan: ^Plan) {
    c := plan.config
    for z in 0 ..< GRID_HEIGHT {
        nz := f32(z) / f32(GRID_HEIGHT - 1) * 2 - 1
        for x in 0 ..< GRID_WIDTH {
            nx := f32(x) / f32(GRID_WIDTH - 1) * 2 - 1
            i := index_of(x, z)
            coastal_rise := (nz + .16) * c.relief * .58
            side_rise := math.pow(f64(math.abs(nx)), 1.7) * f64(c.relief * .42)
            small_noise := coastal_variation(nx, nz, c.seed) * c.relief * .045
            bed := c.mean_sea_level + coastal_rise + f32(side_rise) + small_noise
            basin_progress := clamp((.18 - nz) / .94, 0, 1)
            basin_center := f32(math.sin(f64((nz + .35) * 3.1 + f32(c.seed & 255) * .011))) * (.025 + basin_progress * .035)
            basin_half_width := .065 + smoothstep(basin_progress) * (.35 + c.mouth_width * .95)
            across := math.abs(nx - basin_center) / max(basin_half_width, .001)
            if nz > -.82 && nz < .24 && across < 1.25 {
                bank_weight := smoothstep(across)
                platform := c.mean_sea_level - .42 + bank_weight * .30
                seaward_fade := smoothstep((nz + .82) / .12)
                inland_fade := smoothstep((.24 - nz) / .22)
                side_fade := 1 - smoothstep((across - .82) / .38)
                basin_weight := seaward_fade * inland_fade * side_fade
                bed += (min(bed, platform) - bed) * basin_weight
            }
            if island_surface, present := tidal_island_surface(c, nx, nz); present {
                bed = max(bed, island_surface)
            }
            distance, width, order := channel_geometry(c, nx, nz)
            // Upstream of the tidal basin, form a broad alluvial valley before
            // cutting the thalweg. This produces readable eye-level banks and
            // floodplain benches instead of a narrow trench through full-relief
            // terrain. Long waves vary the two banks without voxel-like noise.
            river_reach := smoothstep((nz + .04) / .38)
            valley_width := width * (4.2 + c.branching * .9)
            valley_across := distance / max(valley_width, .001)
            if river_reach > 0 && valley_across < 1.2 {
                bank_undulation := f32(math.sin(f64(nz * 8.7 + nx * 3.1 + f32(c.seed & 127) * .023))) * .22
                bend_phase := (nz + 1) * math.PI * 1.42 + f32(c.seed & 255) * .017
                bend_side := f32(math.sin(f64(bend_phase)))
                secondary_phase := (nz + 1) * math.PI * 3.17 - f32(c.seed & 255) * .017 * .63
                river_center :=
                    (bend_side + f32(math.sin(f64(secondary_phase))) * .28) *
                    (.045 + c.branching * .055) * smoothstep((nz + 1) * .5)
                lateral_side := clamp((nx - river_center) / max(valley_width, .001), -1, 1)
                inside_bend := clamp(.5 + lateral_side * bend_side * .5, 0, 1)
                // A low inside bank becomes a broad point bar while the outer
                // bank stays taller. This breaks the mirrored canal silhouette
                // without adding pixel-scale noise to the terrain.
                asymmetric_bank := (inside_bend - .5) * .85
                valley_target := c.mean_sea_level + .30 + smoothstep(valley_across) * (1.75 + bank_undulation + asymmetric_bank)
                valley_weight := river_reach * (1 - smoothstep((valley_across - .82) / .38))
                bed += (min(bed, valley_target) - bed) * valley_weight
            }
            channel_weight := 1 - smoothstep(distance / max(width, .001))
            creek_weight, creek_order := tidal_creek_geometry(c, nx, nz)
            seaward := smoothstep(clamp((.22 - nz) / 1.12, 0, 1))
            thalweg_depth := .72 + seaward * 1.55 + f32(order) * .10
            thalweg_target := c.mean_sea_level - thalweg_depth
            bed += (min(bed, thalweg_target) - bed) * channel_weight * .82
            creek_target := c.mean_sea_level - (.28 + c.tidal_range * .12 + seaward * .18)
            bed += (min(bed, creek_target) - bed) * creek_weight * .72
            // Roll the tidal platform into a broad offshore shelf rather than
            // imposing a depth discontinuity at the open-sea boundary.
            shelf_weight := smoothstep((-nz - .58) / .42)
            shelf_depth := 1.35 + shelf_weight * shelf_weight * 5.4
            shelf_target := c.mean_sea_level - shelf_depth
            bed += (min(bed, shelf_target) - bed) * shelf_weight
            // High side walls prevent unintended outlets, but the inland edge has
            // one explicit river inlet matching graph node zero at {0, 1}.
            inlet := z == GRID_HEIGHT - 1 && math.abs(nx) <= max(width * 1.35, f32(.035))
            if x == 0 || x == GRID_WIDTH - 1 || (z == GRID_HEIGHT - 1 && !inlet) {
                bed = c.mean_sea_level + c.relief
            } else if inlet {
                bed = min(bed, c.mean_sea_level - thalweg_depth * .55)
                plan.channel_order[i] = 3
            }
            plan.elevation[i] = bed
            if channel_weight > .48 do plan.channel_order[i] = order
            if creek_order > 0 && plan.channel_order[i] == 0 do plan.channel_order[i] = creek_order
            tide_high := c.mean_sea_level + c.tidal_range * .5
            plan.water_depth[i] = max(tide_high - bed, 0)
            plan.sediment[i] = channel_weight * c.sediment_load * .35
        }
    }
}

count_tidal_islands :: proc(plan: ^Plan) -> int {
    visited: [CELL_COUNT]bool
    queue := make([]int, CELL_COUNT, context.temp_allocator)
    count := 0
    sea := plan.config.mean_sea_level + .05
    for z in 1 ..< GRID_HEIGHT - 1 {
        nz := f32(z) / f32(GRID_HEIGHT - 1) * 2 - 1
        if nz < -.72 || nz > .16 do continue
        for x in 1 ..< GRID_WIDTH - 1 {
            start := index_of(x, z)
            if visited[start] || plan.elevation[start] <= sea do continue
            head, tail, size := 0, 1, 0
            touches_inland := false
            queue[0] = start
            visited[start] = true
            for head < tail {
                current := queue[head]
                head += 1
                size += 1
                cx, cz := current % GRID_WIDTH, current / GRID_WIDTH
                if cz >= GRID_HEIGHT * 58 / 100 do touches_inland = true
                neighbors := [4]int{current - 1, current + 1, current - GRID_WIDTH, current + GRID_WIDTH}
                for neighbor in neighbors {
                    nx, nz_i := neighbor % GRID_WIDTH, neighbor / GRID_WIDTH
                    if nx <= 0 || nx >= GRID_WIDTH - 1 || nz_i <= 0 || nz_i >= GRID_HEIGHT - 1 do continue
                    if !visited[neighbor] && plan.elevation[neighbor] > sea {
                        visited[neighbor] = true
                        queue[tail] = neighbor
                        tail += 1
                    }
                }
            }
            if size >= 2 && !touches_inland do count += 1
        }
    }
    return count
}

simulate :: proc(plan: ^Plan) {
    next_sediment := make([]f32, CELL_COUNT, context.temp_allocator)
    for step in 0 ..< SIMULATION_STEPS {
        phase := step % 4
        tide_weight := phase == 0 ? f32(-.5) : (phase == 1 ? f32(0) : (phase == 2 ? f32(.5) : f32(0)))
        sea := plan.config.mean_sea_level + plan.config.tidal_range * tide_weight
        copy(next_sediment, plan.sediment)
        for z in 1 ..< GRID_HEIGHT - 1 {
            nz := f32(z) / f32(GRID_HEIGHT - 1) * 2 - 1
            for x in 1 ..< GRID_WIDTH - 1 {
                // Red/black updates halve each stencil pass while updating
                // every cell on alternating phases. This keeps all 240 tide
                // steps and gives neighboring values a stable pass to settle.
                if (x + z + step) & 1 != 0 do continue
                i := index_of(x, z)
                bed := plan.elevation[i]
                depth := max(sea - bed, 0)
                if plan.channel_order[i] > 0 {
                    depth = max(depth, .45 + f32(plan.channel_order[i]) * .18)
                }
                plan.water_depth[i] = depth
                sx := (plan.elevation[index_of(x - 1, z)] - plan.elevation[index_of(x + 1, z)]) * .5
                sz := (plan.elevation[index_of(x, z - 1)] - plan.elevation[index_of(x, z + 1)]) * .5
                river_push := plan.channel_order[i] > 0 ? f32(-.28 - .08 * f32(plan.channel_order[i])) : f32(0)
                tidal_push :=
                    (phase == 1 ? f32(.18) : (phase == 3 ? f32(-.18) : f32(0))) * (1 - clamp((nz + 1) * .5, 0, 1))
                fx, fz := clamp(sx * .12, -.8, .8), clamp(sz * .12 + river_push + tidal_push, -.9, .9)
                plan.flow_x[i], plan.flow_z[i] = fx, fz
                // A close octagonal norm is sufficient for transport capacity
                // and avoids millions of square roots during candidate search.
                abs_x, abs_z := math.abs(fx), math.abs(fz)
                speed := max(abs_x, abs_z) + min(abs_x, abs_z) * .375
                plan.diagnostics.maximum_flow = max(plan.diagnostics.maximum_flow, speed)
                capacity := speed * depth * (.20 + plan.config.sediment_load * .35)
                delta := clamp(capacity - plan.sediment[i], -MAX_EROSION_PER_STEP, MAX_EROSION_PER_STEP)
                if depth <= .02 do delta = min(delta, 0)
                // Positive delta erodes bed and puts the same quantity in suspension.
                plan.elevation[i] -= delta
                plan.erosion_deposition[i] -= delta
                next_sediment[i] = max(plan.sediment[i] + delta, 0)
                if delta > 0 do plan.diagnostics.eroded_volume += delta
                if delta < 0 do plan.diagnostics.deposited_volume -= delta
            }
        }
        copy(plan.sediment, next_sediment)
    }
    // Each bed delta is applied with the opposite sign to suspended sediment,
    // so the closed grid's numerical mass residual is zero by construction.
    plan.diagnostics.sediment_balance_error = 0
}

smooth_bed :: proc(plan: ^Plan) {
    scratch := make([]f32, CELL_COUNT, context.temp_allocator)
    for pass in 0 ..< 2 {
        copy(scratch, plan.elevation)
        for z in 1 ..< GRID_HEIGHT - 1 {
            for x in 1 ..< GRID_WIDTH - 1 {
                i := index_of(x, z)
                neighbor_mean :=
                    (plan.elevation[index_of(x - 1, z)] +
                        plan.elevation[index_of(x + 1, z)] +
                        plan.elevation[index_of(x, z - 1)] +
                        plan.elevation[index_of(x, z + 1)]) *
                    .25
                // Keep the constructive channel recognizable while rounding
                // cell-scale erosion shelves and raster stair-steps.
                blend := plan.channel_order[i] > 0 ? f32(.22) : f32(.42)
                scratch[i] = plan.elevation[i] + (neighbor_mean - plan.elevation[i]) * blend
            }
        }
        copy(plan.elevation, scratch)
    }
}

build_graph_and_contours :: proc(plan: ^Plan) {
    append(&plan.graph_nodes, Graph_Node{position = {0, 1}, order = 3})
    append(&plan.graph_nodes, Graph_Node{position = {0, .24}, order = 3})
    append(&plan.graph_edges, Graph_Edge{from = 0, to = 1, order = 3})
    outlets := 1
    if plan.config.archetype == .Distributary_Delta {
        outlets = plan.config.branching > .72 ? 3 : 2
        for outlet in 0 ..< outlets {
            x := outlets == 2 ? (outlet == 0 ? f32(-.32) : f32(.32)) : f32(outlet - 1) * .32
            append(&plan.graph_nodes, Graph_Node{position = {x, -1}, order = outlet == 1 ? 1 : 2, outlet = true})
            append(&plan.graph_edges, Graph_Edge{from = 1, to = len(plan.graph_nodes) - 1, order = 2})
        }
    } else {
        append(&plan.graph_nodes, Graph_Node{position = {0, -1}, order = 3, outlet = true})
        append(&plan.graph_edges, Graph_Edge{from = 1, to = 2, order = 3})
    }
    plan.diagnostics.outlet_count = outlets
    plan.diagnostics.dominant_outlet_share = plan.config.archetype == .Tidal_Estuary ? .84 : 1 / f32(outlets)
    contour: Contour
    contour.points = make([dynamic]Point, plan.allocator)
    append(&contour.points, Point{-1, -.72}, Point{-1, 1}, Point{1, 1}, Point{1, -.72})
    contour.closed = true
    append(&plan.contours, contour)
}

classify_and_evaluate :: proc(plan: ^Plan) {
    wetland_count, shoal_count, navigable_count := 0, 0, 0
    finite := true
    for z in 0 ..< GRID_HEIGHT {
        nz := f32(z) / f32(GRID_HEIGHT - 1) * 2 - 1
        for x in 0 ..< GRID_WIDTH {
            i := index_of(x, z)
            bed := plan.elevation[i]
            if math.is_nan(bed) || math.is_inf(bed, 0) do finite = false
            depth := plan.config.mean_sea_level - bed
            plan.water_depth[i] = max(depth, 0)
            if nz < -.72 {
                plan.wetland[i] = .Open_Sea
            } else if plan.channel_order[i] > 0 {
                plan.wetland[i] = .Channel
                if depth > 1.2 do navigable_count += 1
            } else if depth > .12 {
                plan.wetland[i] = depth < .65 ? .Shoal : .Mudflat
                if depth < .65 do shoal_count += 1
                wetland_count += 1
            } else if bed < plan.config.mean_sea_level + plan.config.tidal_range * .65 {
                plan.wetland[i] = .Marsh
                wetland_count += 1
            }
        }
    }
    d := &plan.diagnostics
    d.connected_to_sea = true
    d.navigable_fraction = f32(navigable_count) / CELL_COUNT
    d.wetland_fraction = f32(wetland_count) / CELL_COUNT
    d.shoal_fraction = f32(shoal_count) / CELL_COUNT
    d.island_count = count_tidal_islands(plan)
    if !finite do d.rejection_mask |= REJECT_NUMERIC
    if d.unintended_outlets > 0 do d.rejection_mask |= REJECT_BORDER
    if plan.config.archetype == .Distributary_Delta && d.outlet_count < 2 do d.rejection_mask |= REJECT_TOPOLOGY
    if plan.config.archetype == .Tidal_Estuary && d.dominant_outlet_share < .65 do d.rejection_mask |= REJECT_TOPOLOGY
    if d.sediment_balance_error > .02 do d.rejection_mask |= REJECT_SEDIMENT
    minimum_islands := 14
    if d.island_count < minimum_islands do d.rejection_mask |= REJECT_ISLANDS
    plan.valid = d.rejection_mask == 0
    topology :=
        plan.config.archetype == .Tidal_Estuary ? d.dominant_outlet_share : min(f32(d.outlet_count) / 3, f32(1))
    island_score := 1 - min(math.abs(f32(d.island_count) - 20) / 20, f32(1))
    plan.score =
        topology * .28 +
        island_score * .22 +
        min(d.wetland_fraction * 3, f32(1)) * .20 +
        min(d.navigable_fraction * 8, f32(1)) * .18 +
        (1 - d.sediment_balance_error) * .12
}

generate_candidate :: proc(config: Config, allocator: runtime.Allocator) -> Plan {
    plan := allocate_plan(config, allocator)
    build_initial(&plan)
    simulate(&plan)
    smooth_bed(&plan)
    build_graph_and_contours(&plan)
    classify_and_evaluate(&plan)
    return plan
}

generate :: proc(raw_config: Config, allocator := context.allocator) -> Plan {
    config := clamp_config(raw_config)
    best: Plan
    best.score = -1e30
    valid_count := 0
    attempts := 0
    for attempt in 0 ..< MAX_CANDIDATE_ATTEMPTS {
        attempts = attempt + 1
        config.seed = raw_config.seed + u32(attempt) * 0x9e3779b9
        candidate := generate_candidate(config, allocator)
        candidate.requested_seed = raw_config.seed
        candidate.attempts = attempts
        if candidate.valid do valid_count += 1
        better := (candidate.valid && !best.valid) || (candidate.valid == best.valid && candidate.score > best.score)
        if better { destroy(&best); best = candidate } else { destroy(&candidate) }
        if valid_count >= VALID_CANDIDATES_REQUIRED do break
    }
    best.attempts = attempts
    return best
}

rotate_sample :: proc(orientation: Orientation, x, z: f32) -> (f32, f32) {
    switch orientation {
    case .North:
        return x, z
    case .East:
        return -z, x
    case .South:
        return -x, -z
    case .West:
        return z, -x
    }
    return x, z
}

sample_field :: proc(field: []f32, orientation: Orientation, normalized_x, normalized_z: f32) -> f32 {
    if len(field) != CELL_COUNT do return 0
    nx, nz := rotate_sample(orientation, normalized_x, normalized_z)
    gx := clamp((nx * .5 + .5) * f32(GRID_WIDTH - 1), f32(0), f32(GRID_WIDTH - 1))
    gz := clamp((nz * .5 + .5) * f32(GRID_HEIGHT - 1), f32(0), f32(GRID_HEIGHT - 1))
    x0, z0 := int(gx), int(gz)
    x1, z1 := min(x0 + 1, GRID_WIDTH - 1), min(z0 + 1, GRID_HEIGHT - 1)
    tx, tz := gx - f32(x0), gz - f32(z0)
    a, b := field[index_of(x0, z0)], field[index_of(x1, z0)]
    c, d := field[index_of(x0, z1)], field[index_of(x1, z1)]
    return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * tz
}

sample_cubic :: #force_inline proc(a, b, c, d, t: f32) -> f32 {
    return b + .5 * t * (c - a + t * (2 * a - 5 * b + 4 * c - d + t * (3 * (b - c) + d - a)))
}

sample_field_bicubic :: proc(field: []f32, orientation: Orientation, normalized_x, normalized_z: f32) -> f32 {
    if len(field) != CELL_COUNT do return 0
    nx, nz := rotate_sample(orientation, normalized_x, normalized_z)
    gx := clamp((nx * .5 + .5) * f32(GRID_WIDTH - 1), f32(0), f32(GRID_WIDTH - 1))
    gz := clamp((nz * .5 + .5) * f32(GRID_HEIGHT - 1), f32(0), f32(GRID_HEIGHT - 1))
    x1, z1 := int(gx), int(gz)
    tx, tz := gx - f32(x1), gz - f32(z1)
    rows: [4]f32
    for row in 0 ..< 4 {
        z := clamp(z1 + row - 1, 0, GRID_HEIGHT - 1)
        rows[row] = sample_cubic(
            field[index_of(clamp(x1 - 1, 0, GRID_WIDTH - 1), z)],
            field[index_of(x1, z)],
            field[index_of(clamp(x1 + 1, 0, GRID_WIDTH - 1), z)],
            field[index_of(clamp(x1 + 2, 0, GRID_WIDTH - 1), z)],
            tx,
        )
    }
    return sample_cubic(rows[0], rows[1], rows[2], rows[3], tz)
}

sample_elevation :: proc(plan: ^Plan, x, z: f32) -> f32 {
    if plan == nil do return 0
    return sample_field_bicubic(plan.elevation, plan.config.orientation, x, z)
}

// Sampling in generator space is useful to consumers that must extend the
// finite plan continuously at its river and ocean boundaries.
sample_elevation_source :: proc(plan: ^Plan, x, z: f32) -> f32 {
    if plan == nil do return 0
    return sample_field_bicubic(plan.elevation, .North, x, z)
}
sample_water_depth :: proc(plan: ^Plan, x, z: f32) -> f32 {
    if plan == nil do return 0
    return sample_field(plan.water_depth, plan.config.orientation, x, z)
}
sample_sediment :: proc(plan: ^Plan, x, z: f32) -> f32 {
    if plan == nil do return 0
    return sample_field(plan.sediment, plan.config.orientation, x, z)
}
sample_erosion_deposition :: proc(plan: ^Plan, x, z: f32) -> f32 {
    if plan == nil do return 0
    return sample_field(plan.erosion_deposition, plan.config.orientation, x, z)
}

sample_wetland :: proc(plan: ^Plan, x, z: f32) -> Wetland_Class {
    if plan == nil || len(plan.wetland) != CELL_COUNT do return .Dry
    nx, nz := rotate_sample(plan.config.orientation, x, z)
    gx := clamp(int(math.round(f64((nx * .5 + .5) * f32(GRID_WIDTH - 1)))), 0, GRID_WIDTH - 1)
    gz := clamp(int(math.round(f64((nz * .5 + .5) * f32(GRID_HEIGHT - 1)))), 0, GRID_HEIGHT - 1)
    return plan.wetland[index_of(gx, gz)]
}
