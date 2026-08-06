package islands

import markov "zelda_engine:markov"
import "base:runtime"
import "core:math"

GRID_WIDTH :: 96
GRID_HEIGHT :: 64
CELL_COUNT :: GRID_WIDTH * GRID_HEIGHT
MAX_CANDIDATE_ATTEMPTS :: 8
VALID_CANDIDATES_REQUIRED :: 3
MIN_SKERRY_CELLS :: 5
MAX_CONTOURS :: 64
FOLIAGE_LATTICE_STEP :: 4

Cell :: enum u8 {
    Water,
    Land,
}

Contour_Kind :: enum u8 {
    Main_Coast,
    Lake,
    Skerry,
}

Shape_Archetype :: enum u8 {
    Dinaric_Ridge,
    Forked_Ridge,
    Embayed_Plateau,
    Twin_Lobed,
    Broken_Ridge,
}

shape_archetype_name :: proc(shape: Shape_Archetype) -> string {
    switch shape {
    case .Dinaric_Ridge:
        return "DINARIC RIDGE"
    case .Forked_Ridge:
        return "FORKED RIDGE"
    case .Embayed_Plateau:
        return "EMBAYED PLATEAU"
    case .Twin_Lobed:
        return "TWIN LOBED"
    case .Broken_Ridge:
        return "BROKEN RIDGE"
    }
    return "UNKNOWN"
}

Point :: struct {
    x, z: f32,
}

// Foliage patches are expressed in the generator's normalized island space.
// Keeping them product-neutral lets callers realize the plan with their own
// vegetation system while preserving the island seed's composition.
Foliage_Patch :: struct {
    x, z:         f32,
    width, depth: f32,
    height:       f32,
    rotation:     f32,
    seed:         u32,
}

Contour :: struct {
    kind:   Contour_Kind,
    points: [dynamic]Point,
    area:   f32,
}

Bounds :: struct {
    min_x, min_z: int,
    max_x, max_z: int,
}

Diagnostics :: struct {
    land_cells:           int,
    main_land_cells:      int,
    water_cells:          int,
    coastline_edges:      int,
    component_count:      int,
    lake_count:           int,
    skerry_count:         int,
    narrow_neck_cells:    int,
    border_land_cells:    int,
    coastline_complexity: f32,
    aspect_ratio:         f32,
    rectangularity:       f32,
    bluff_cells:          int,
    maximum_elevation:    f32,
    rejection_mask:       u32,
}

REJECT_AREA :: u32(1 << 0)
REJECT_BORDER :: u32(1 << 1)
REJECT_FRAGMENTATION :: u32(1 << 2)
REJECT_NECKS :: u32(1 << 3)
REJECT_CONTOURS :: u32(1 << 4)

Plan :: struct {
    requested_seed:  u32,
    selected_seed:   u32,
    attempts:        int,
    valid:           bool,
    score:           f32,
    shape:           Shape_Archetype,
    source:          []Cell,
    cleaned:         []Cell,
    signed_distance: []f32,
    elevation:       []f32,
    bluff:           []f32,
    contours:        [dynamic]Contour,
    foliage:         [dynamic]Foliage_Patch,
    bounds:          Bounds,
    diagnostics:     Diagnostics,
    allocator:       runtime.Allocator,
}

destroy :: proc(plan: ^Plan) {
    if plan == nil do return
    for &contour in plan.contours {
        delete(contour.points)
    }
    delete(plan.contours)
    delete(plan.foliage)
    delete(plan.source, plan.allocator)
    delete(plan.cleaned, plan.allocator)
    delete(plan.signed_distance, plan.allocator)
    delete(plan.elevation, plan.allocator)
    delete(plan.bluff, plan.allocator)
    plan^ = {}
}

build_foliage :: proc(plan: ^Plan, seed: u32) {
    if plan == nil do return
    plan.foliage = make([dynamic]Foliage_Patch, plan.allocator)
    // A jittered coarse lattice produces separated groves instead of a
    // uniform carpet. Inland distance keeps beaches and lake margins open;
    // bluff rejection preserves exposed rock faces.
    for z := FOLIAGE_LATTICE_STEP; z < GRID_HEIGHT - FOLIAGE_LATTICE_STEP; z += FOLIAGE_LATTICE_STEP {
        for x := FOLIAGE_LATTICE_STEP; x < GRID_WIDTH - FOLIAGE_LATTICE_STEP; x += FOLIAGE_LATTICE_STEP {
            salt := hash(seed ~ u32(index_of(x, z)) ~ 0x464f4c49)
            jitter_x := int(salt & 3) - 1
            jitter_z := int((salt >> 2) & 3) - 1
            sample_x := clamp(x + jitter_x, 0, GRID_WIDTH - 1)
            sample_z := clamp(z + jitter_z, 0, GRID_HEIGHT - 1)
            index := index_of(sample_x, sample_z)
            inland := -plan.signed_distance[index]
            if plan.cleaned[index] != .Land || inland < 3.8 || plan.bluff[index] > .38 || plan.elevation[index] < 2.5 {
                continue
            }
            moisture := hash(salt ~ 0x47524f57) & 255
            // Valleys and sheltered low slopes carry denser vegetation, while
            // high ground retains occasional wind-shaped copses.
            threshold := plan.elevation[index] < 15 ? u32(104) : u32(58)
            if moisture >= threshold do continue
            width := .055 + f32((salt >> 8) & 255) / 255 * .055
            depth := .050 + f32((salt >> 16) & 255) / 255 * .050
            append(
                &plan.foliage,
                Foliage_Patch {
                    x = f32(sample_x) / f32(GRID_WIDTH - 1) * 2 - 1,
                    z = f32(sample_z) / f32(GRID_HEIGHT - 1) * 2 - 1,
                    width = width,
                    depth = depth,
                    height = .035 + f32((salt >> 24) & 255) / 255 * .045,
                    rotation = f32(salt & 0xffff) / 65535 * f32(math.PI),
                    seed = hash(salt ~ 0x53454544),
                },
            )
        }
    }
}

hash :: proc(value: u32) -> u32 {
    x := value
    x = x ~ (x >> 16)
    x *= 0x7feb352d
    x = x ~ (x >> 15)
    x *= 0x846ca68b
    return x ~ (x >> 16)
}

model :: proc(allocator := context.allocator) -> markov.Proc_Node {
    spine := markov.node(
        markov.Proc_Tag.one,
        []markov.Proc_Attr{markov.kattr(.in_, "10"), markov.kattr(.out, "11"), markov.kattr(.steps, 38)},
        allocator = allocator,
    )
    branch := markov.node(
        markov.Proc_Tag.one,
        []markov.Proc_Attr {
            markov.kattr(.in_, "10"),
            markov.kattr(.out, "11"),
            markov.kattr(.steps, 210),
            markov.kattr(.symmetry, "(xy)"),
        },
        allocator = allocator,
    )
    shoulder := markov.node(
        markov.Proc_Tag.one,
        []markov.Proc_Attr {
            markov.kattr(.in_, "11/00"),
            markov.kattr(.out, "11/11"),
            markov.kattr(.steps, 330),
            markov.kattr(.symmetry, "(xy)"),
        },
        allocator = allocator,
    )
    // The sequence takes ownership of its children.
    result := markov.node(
        markov.Proc_Tag.sequence,
        []markov.Proc_Attr {
            markov.kattr(.values, markov.values_count(2)),
            markov.kattr(.origin, true),
            // Keep the long axis stable while stochastic matches make its
            // endpoints and branch locations seed-dependent.
            markov.kattr(.symmetry, "(x)"),
        },
        []markov.Proc_Node{spine, branch, shoulder},
        allocator = allocator,
    )
    return result
}

run_markov :: proc(seed: u32, destination: []Cell) -> bool {
    tree := model(context.temp_allocator)
    ip, ok := markov.load_model_proc(tree, {GRID_WIDTH, GRID_HEIGHT, 1}, context.temp_allocator)
    if !ok do return false
    defer markov.interpreter_destroy(ip)
    frames := markov.run(ip, int(seed), 0, false, context.temp_allocator)
    defer markov.frames_destroy(&frames, context.temp_allocator)
    if len(frames) == 0 do return false
    final := &frames[len(frames) - 1]
    if len(final.state) != CELL_COUNT do return false
    for value, index in final.state {
        destination[index] = value == 0 ? .Water : .Land
    }
    return true
}

index_of :: #force_inline proc(x, z: int) -> int {
    return z * GRID_WIDTH + x
}

in_bounds :: #force_inline proc(x, z: int) -> bool {
    return x >= 0 && x < GRID_WIDTH && z >= 0 && z < GRID_HEIGHT
}

is_land :: #force_inline proc(cells: []Cell, x, z: int) -> bool {
    return in_bounds(x, z) && cells[index_of(x, z)] == .Land
}

shape_archetype :: #force_inline proc(seed: u32) -> Shape_Archetype {
    roll := hash(seed ~ 0x53484150) % 100
    if roll < 35 do return .Dinaric_Ridge
    if roll < 55 do return .Forked_Ridge
    if roll < 75 do return .Embayed_Plateau
    if roll < 90 do return .Twin_Lobed
    return .Broken_Ridge
}

shape_ellipse_contains :: #force_inline proc(x, z, center_x, center_z, half_x, half_z: f32) -> bool {
    dx := (x - center_x) / max(half_x, f32(.001))
    dz := (z - center_z) / max(half_z, f32(.001))
    return dx * dx + dz * dz < 1
}

shape_macro_contains :: proc(archetype: Shape_Archetype, nx, nz, phase: f32) -> bool {
    bend := f32(math.sin(f64(nx * 2.4 + phase))) * .10 + f32(math.sin(f64(nx * 5.1 - phase))) * .035
    taper := f32(math.sqrt(f64(max(1 - nx * nx, 0))))
    width_noise := 1 + f32(math.sin(f64(nx * 4.3 + phase * 1.7))) * .12
    asymmetric_width := nz >= bend ? f32(.90) : f32(1.10)

    switch archetype {
    case .Dinaric_Ridge:
        return math.abs(nz - bend) < (.44 * taper + .055) * width_noise * asymmetric_width
    case .Forked_Ridge:
        trunk := math.abs(nz - bend) < (.38 * taper + .05) * width_noise
        fork_up := shape_ellipse_contains(nx, nz, .38, .24, .52, .22)
        fork_down := shape_ellipse_contains(nx, nz, .48, -.22, .40, .18)
        return trunk || fork_up || fork_down
    case .Embayed_Plateau:
        body := shape_ellipse_contains(nx, nz, -.08, 0, .98, .62)
        north_bay := shape_ellipse_contains(nx, nz, .18, -.58, .30, .28)
        east_bay := shape_ellipse_contains(nx, nz, .76, .08, .30, .25)
        return body && !north_bay && !east_bay
    case .Twin_Lobed:
        west := shape_ellipse_contains(nx, nz, -.42, -.05, .59, .52)
        east := shape_ellipse_contains(nx, nz, .43, .07, .62, .45)
        neck := shape_ellipse_contains(nx, nz, 0, 0, .34, .20)
        return west || east || neck
    case .Broken_Ridge:
        body := math.abs(nz - bend) < (.34 * taper + .045) * width_noise
        sound := shape_ellipse_contains(nx, nz, .63, bend + .02, .10, .32)
        terminal := shape_ellipse_contains(nx, nz, .86, bend - .03, .17, .20)
        return (body && !sound) || terminal
    }
    return false
}

// Grow the coarse MJ skeleton into an archetype-shaped land mass. The spine,
// lobes, forks, and negative bay volumes establish the large-scale silhouette;
// the cellular source contributes only local variation.
shape_source :: proc(cells: []Cell, seed: u32) -> Shape_Archetype {
    original: [CELL_COUNT]Cell
    copy(original[:], cells)
    cx, cz := f32(GRID_WIDTH - 1) * .5, f32(GRID_HEIGHT - 1) * .5
    phase := f32(hash(seed) & 0xffff) / 65535 * f32(math.PI * 2)
    archetype := shape_archetype(seed)
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            near := false
            for dz in -5 ..= 5 {
                for dx in -5 ..= 5 {
                    if dx * dx + dz * dz > 25 do continue
                    if is_land(original[:], x + dx, z + dz) {
                        near = true
                        break
                    }
                }
                if near do break
            }
            nx := (f32(x) - cx) / 43
            nz := (f32(z) - cz) / 27
            macro_land := shape_macro_contains(archetype, nx, nz, phase)
            // Preserve occasional coves cut by the Markov field, but allow the
            // macroform to fill enough of its spine to remain legible.
            local_fill := f32(hash(seed ~ u32(index_of(x, z))) & 255) / 255
            cells[index_of(x, z)] = macro_land && (near || local_fill > .86) ? .Land : .Water
        }
    }

    // Secondary topology is an optional consequence of the same seeded
    // coastal process, not a quota. Interior dissolution may open no basin at
    // all, or several irregular lakes. Offshore deposition likewise produces
    // zero or more fragments, some of which reconnect to the main coast or are
    // discarded as noise during cleanup.
    basin_attempts := int(hash(seed ~ 0x4c414b45) % 4)
    for ordinal in 0 ..< basin_attempts {
        salt := seed ~ u32(ordinal * 0x9e37) ~ 0x57415452
        basin_x := GRID_WIDTH / 2 + int(hash(salt) % 31) - 15
        basin_z := GRID_HEIGHT / 2 + int(hash(salt ~ 0x1111) % 21) - 10
        radius_x := 1 + int(hash(salt ~ 0x2222) % 5)
        radius_z := 1 + int(hash(salt ~ 0x3333) % 4)
        if !is_land(cells, basin_x, basin_z) do continue
        // Require an inland collar. Failed attempts naturally become coves
        // only when they already lie close to open water.
        inland := true
        directions := [4][2]int{{-(radius_x + 2), 0}, {radius_x + 2, 0}, {0, -(radius_z + 2)}, {0, radius_z + 2}}
        for direction in directions {
            if !is_land(cells, basin_x + direction.x, basin_z + direction.y) {
                inland = false
                break
            }
        }
        if !inland do continue
        for z in basin_z - radius_z ..= basin_z + radius_z {
            for x in basin_x - radius_x ..= basin_x + radius_x {
                if !in_bounds(x, z) do continue
                dx := f32(x - basin_x) / f32(radius_x)
                dz := f32(z - basin_z) / f32(radius_z)
                edge_noise := f32(hash(salt ~ u32(index_of(x, z))) & 255) / 255
                if dx * dx + dz * dz < .72 + edge_noise * .38 {
                    cells[index_of(x, z)] = .Water
                }
            }
        }
    }

    fragment_attempts := int(hash(seed ~ 0x534b4552) % 6)
    for ordinal in 0 ..< fragment_attempts {
        salt := seed ~ u32(ordinal * 0x85eb) ~ 0x4445504f
        angle := f32(hash(salt) & 0xffff) / 65535 * f32(math.PI * 2)
        radial := 1.03 + f32(hash(salt ~ 0x1111) & 255) / 255 * .18
        sx := int(cx + f32(math.cos(f64(angle))) * 43 * radial)
        sz := int(cz + f32(math.sin(f64(angle))) * 27 * radial)
        radius := 1 + int(hash(salt ~ 0x2222) % 4)
        for z in sz - radius ..= sz + radius {
            for x in sx - radius ..= sx + radius {
                if !in_bounds(x, z) do continue
                dx, dz := x - sx, z - sz
                roughness := int(hash(salt ~ u32(index_of(x, z))) % 3)
                if dx * dx + dz * dz <= radius * radius - roughness {
                    cells[index_of(x, z)] = .Land
                }
            }
        }
    }
    return archetype
}

component_labels :: proc(cells: []Cell, land: bool, labels: []i16, sizes: ^[256]int) -> int {
    for &value in labels do value = -1
    sizes^ = {}
    count := 0
    queue: [CELL_COUNT]int
    for start in 0 ..< CELL_COUNT {
        occupied := cells[start] == .Land
        if occupied != land || labels[start] >= 0 do continue
        if count >= len(sizes) do break
        head, tail := 0, 1
        queue[0] = start
        labels[start] = i16(count)
        for head < tail {
            current := queue[head]
            head += 1
            x, z := current % GRID_WIDTH, current / GRID_WIDTH
            sizes[count] += 1
            neighbors := [4][2]int{{x - 1, z}, {x + 1, z}, {x, z - 1}, {x, z + 1}}
            for neighbor in neighbors {
                if !in_bounds(neighbor.x, neighbor.y) do continue
                ni := index_of(neighbor.x, neighbor.y)
                if labels[ni] >= 0 || (cells[ni] == .Land) != land do continue
                labels[ni] = i16(count)
                queue[tail] = ni
                tail += 1
            }
        }
        count += 1
    }
    return count
}

cleanup :: proc(source, result: []Cell) {
    copy(result, source)
    labels: [CELL_COUNT]i16
    sizes: [256]int
    count := component_labels(source, true, labels[:], &sizes)
    main := 0
    for component in 1 ..< count {
        if sizes[component] > sizes[main] do main = component
    }
    for index in 0 ..< CELL_COUNT {
        if source[index] == .Land && int(labels[index]) != main && sizes[int(labels[index])] < MIN_SKERRY_CELLS {
            result[index] = .Water
        }
    }

    // One conservative majority pass removes cellular spikes and pinholes.
    previous: [CELL_COUNT]Cell
    copy(previous[:], result)
    for z in 1 ..< GRID_HEIGHT - 1 {
        for x in 1 ..< GRID_WIDTH - 1 {
            neighbors := 0
            for dz in -1 ..= 1 {
                for dx in -1 ..= 1 {
                    if dx == 0 && dz == 0 do continue
                    if is_land(previous[:], x + dx, z + dz) do neighbors += 1
                }
            }
            index := index_of(x, z)
            if previous[index] == .Land && neighbors <= 2 do result[index] = .Water
            if previous[index] == .Water && neighbors >= 7 do result[index] = .Land
        }
    }
}

build_signed_distance :: proc(cells: []Cell, destination: []f32) {
    boundary_indices: [CELL_COUNT]int
    boundary_count := 0
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            land := is_land(cells, x, z)
            index := index_of(x, z)
            is_boundary :=
                land != is_land(cells, x - 1, z) ||
                land != is_land(cells, x + 1, z) ||
                land != is_land(cells, x, z - 1) ||
                land != is_land(cells, x, z + 1)
            if is_boundary {
                boundary_indices[boundary_count] = index
                boundary_count += 1
            }
        }
    }
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            best := f32(1e9)
            for boundary_index in boundary_indices[:boundary_count] {
                bx, bz := boundary_index % GRID_WIDTH, boundary_index / GRID_WIDTH
                dx, dz := f32(x - bx), f32(z - bz)
                best = min(best, dx * dx + dz * dz)
            }
            distance := f32(math.sqrt(f64(best))) + .5
            destination[index_of(x, z)] = is_land(cells, x, z) ? -distance : distance
        }
    }
    // A compact tent filter turns the exact grid transform into a continuous
    // scalar coast. Preserve the original sign so narrow lakes and skerries
    // cannot disappear merely because their distance samples were filtered.
    original: [CELL_COUNT]f32
    copy(original[:], destination)
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            sum, weight := f32(0), f32(0)
            for dz in -1 ..= 1 {
                for dx in -1 ..= 1 {
                    sx, sz := clamp(x + dx, 0, GRID_WIDTH - 1), clamp(z + dz, 0, GRID_HEIGHT - 1)
                    w := (dx == 0 ? f32(2) : f32(1)) * (dz == 0 ? f32(2) : f32(1))
                    sum += original[index_of(sx, sz)] * w
                    weight += w
                }
            }
            filtered := sum / weight
            original_value := original[index_of(x, z)]
            destination[index_of(x, z)] = original_value < 0 ? min(filtered, f32(-.05)) : max(filtered, f32(.05))
        }
    }
}

smooth_weight :: #force_inline proc(value: f32) -> f32 {
    t := clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
}

macro_highland_direction :: #force_inline proc(seed: u32) -> (x, z: f32) {
    angle := f32(hash(seed ~ 0x4d414352) & 0xffff) / 65535 * f32(math.PI * 2)
    return f32(math.cos(f64(angle))), f32(math.sin(f64(angle)))
}

macro_highland_weight :: #force_inline proc(seed: u32, normalized_x, normalized_z: f32) -> f32 {
    direction_x, direction_z := macro_highland_direction(seed)
    projection := normalized_x * direction_x + normalized_z * direction_z
    return smooth_weight((projection + .22) / .58)
}

build_vertical_form :: proc(plan: ^Plan, seed: u32) {
    hill_count := 3 + int(hash(seed ~ 0x48494c4c) % 4)
    bluff_count := 1 + int(hash(seed ~ 0x424c5546) % 3)
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            index := index_of(x, z)
            distance := plan.signed_distance[index]
            if distance >= 0 do continue
            inland := -distance
            nx := f32(x) / f32(GRID_WIDTH - 1) * 2 - 1
            nz := f32(z) / f32(GRID_HEIGHT - 1) * 2 - 1
            shore_rise := smooth_weight(inland / 4.5)
            highland := macro_highland_weight(seed, nx, nz)
            relief_noise := f32(math.sin(f64(nx * 7.1 + nz * 3.4 + f32(seed & 255) * .013)))
            // One broad half trends lower for settlement, agriculture, and
            // airfield circulation. Relief remains possible everywhere; the
            // opposing half is only biased toward a stronger mountain spine.
            elevation :=
                shore_rise * (2.2 + relief_noise * (.35 + highland * .65) + highland * (5.2 + relief_noise * 1.1))

            // Overlapping anisotropic uplifts form ridge chains and distinct
            // high points without prescribing a single central summit.
            for hill_index in 0 ..< hill_count {
                salt := seed ~ u32(hill_index * 0x9e37) ~ 0x52494447
                center_x := f32(int(hash(salt) % 61) - 30) / 48
                center_z := f32(int(hash(salt ~ 0x1111) % 39) - 19) / 32
                half_x := .18 + f32(hash(salt ~ 0x2222) & 255) / 255 * .34
                half_z := .12 + f32(hash(salt ~ 0x3333) & 255) / 255 * .26
                rotation := f32(hash(salt ~ 0x4444) & 0xffff) / 65535 * f32(math.PI)
                cosine, sine := f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))
                dx, dz := nx - center_x, nz - center_z
                local_x := (dx * cosine + dz * sine) / half_x
                local_z := (-dx * sine + dz * cosine) / half_z
                weight := smooth_weight(1 - local_x * local_x - local_z * local_z)
                height := 7 + f32(hash(salt ~ 0x5555) & 255) / 255 * 17
                elevation += weight * height * shore_rise * (.45 + highland * .75)
            }

            // The distance gradient supplies the local outward coast normal.
            // Seeded prevailing directions select connected bluff faces.
            left := plan.signed_distance[index_of(max(x - 1, 0), z)]
            right := plan.signed_distance[index_of(min(x + 1, GRID_WIDTH - 1), z)]
            up := plan.signed_distance[index_of(x, max(z - 1, 0))]
            down := plan.signed_distance[index_of(x, min(z + 1, GRID_HEIGHT - 1))]
            gradient_x, gradient_z := right - left, down - up
            gradient_length := f32(math.sqrt(f64(gradient_x * gradient_x + gradient_z * gradient_z)))
            bluff_weight := f32(0)
            if gradient_length > .001 && inland < 12 {
                normal_x, normal_z := gradient_x / gradient_length, gradient_z / gradient_length
                for bluff_index in 0 ..< bluff_count {
                    salt := seed ~ u32(bluff_index * 0x85eb) ~ 0x46414345
                    angle := f32(hash(salt) & 0xffff) / 65535 * f32(math.PI * 2)
                    direction_x := f32(math.cos(f64(angle)))
                    direction_z := f32(math.sin(f64(angle)))
                    facing := normal_x * direction_x + normal_z * direction_z
                    directional := smooth_weight((facing - .28) / .55)
                    along_noise := .72 + f32(math.sin(f64(nx * 8.3 - nz * 6.7 + angle * 2))) * .28
                    band := smooth_weight(inland / 2.2) * (1 - smooth_weight((inland - 7) / 5))
                    bluff_weight = max(bluff_weight, directional * along_noise * band)
                }
            }
            plan.bluff[index] = clamp(bluff_weight, 0, 1)
            bluff_height := 8 + f32(hash(seed ~ 0x48454947) & 255) / 255 * 10
            elevation += plan.bluff[index] * bluff_height
            plan.elevation[index] = max(elevation, f32(.08))
            if plan.bluff[index] > .35 do plan.diagnostics.bluff_cells += 1
            plan.diagnostics.maximum_elevation = max(plan.diagnostics.maximum_elevation, plan.elevation[index])
        }
    }
}

Edge :: struct {
    ax, az, bx, bz: int,
}

edge_equal_start :: #force_inline proc(edge: Edge, x, z: int) -> bool {
    return edge.ax == x && edge.az == z
}

sample_distance_grid :: proc(plan: ^Plan, x, z: f32) -> f32 {
    // Contour coordinates lie on cell edges while distance samples live at
    // cell centers, hence the half-cell offset.
    gx := clamp(x - .5, f32(0), f32(GRID_WIDTH - 1))
    gz := clamp(z - .5, f32(0), f32(GRID_HEIGHT - 1))
    x0, z0 := int(gx), int(gz)
    x1, z1 := min(x0 + 1, GRID_WIDTH - 1), min(z0 + 1, GRID_HEIGHT - 1)
    tx, tz := gx - f32(x0), gz - f32(z0)
    a := plan.signed_distance[index_of(x0, z0)]
    b := plan.signed_distance[index_of(x1, z0)]
    c := plan.signed_distance[index_of(x0, z1)]
    d := plan.signed_distance[index_of(x1, z1)]
    top, bottom := a + (b - a) * tx, c + (d - c) * tx
    return top + (bottom - top) * tz
}

project_contour_to_bilinear_isoline :: proc(plan: ^Plan, contour: ^Contour) {
    if contour == nil do return
    for &point in contour.points {
        for _ in 0 ..< 3 {
            value := sample_distance_grid(plan, point.x, point.z)
            epsilon := f32(.2)
            gradient_x :=
                (sample_distance_grid(plan, point.x + epsilon, point.z) -
                    sample_distance_grid(plan, point.x - epsilon, point.z)) /
                (epsilon * 2)
            gradient_z :=
                (sample_distance_grid(plan, point.x, point.z + epsilon) -
                    sample_distance_grid(plan, point.x, point.z - epsilon)) /
                (epsilon * 2)
            magnitude := gradient_x * gradient_x + gradient_z * gradient_z
            if magnitude < .0001 do break
            step := clamp(value / magnitude, f32(-.7), f32(.7))
            point.x -= gradient_x * step
            point.z -= gradient_z * step
        }
    }
}

round_contour :: proc(plan: ^Plan, contour: ^Contour) {
    if contour == nil || len(contour.points) < 4 do return
    // Chaikin corner cutting removes right-angle remnants after the bilinear
    // zero-isoline projection. One pass retains bays and small skerries.
    rounded := make([dynamic]Point, 0, len(contour.points) * 2, plan.allocator)
    for index in 0 ..< len(contour.points) {
        a := contour.points[index]
        b := contour.points[(index + 1) % len(contour.points)]
        append(&rounded, Point{a.x * .75 + b.x * .25, a.z * .75 + b.z * .25})
        append(&rounded, Point{a.x * .25 + b.x * .75, a.z * .25 + b.z * .75})
    }
    delete(contour.points)
    contour.points = rounded
    project_contour_to_bilinear_isoline(plan, contour)
}

append_contours :: proc(plan: ^Plan, main_component: int, labels: []i16) {
    edges := make([dynamic]Edge, context.temp_allocator)
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            if !is_land(plan.cleaned, x, z) do continue
            // Clockwise edges put land on the right. Outer loops and holes
            // therefore receive opposite signed areas automatically.
            if !is_land(plan.cleaned, x, z - 1) do append(&edges, Edge{x, z, x + 1, z})
            if !is_land(plan.cleaned, x + 1, z) do append(&edges, Edge{x + 1, z, x + 1, z + 1})
            if !is_land(plan.cleaned, x, z + 1) do append(&edges, Edge{x + 1, z + 1, x, z + 1})
            if !is_land(plan.cleaned, x - 1, z) do append(&edges, Edge{x, z + 1, x, z})
        }
    }
    used := make([]bool, len(edges), context.temp_allocator)
    for first in 0 ..< len(edges) {
        if used[first] || len(plan.contours) >= MAX_CONTOURS do continue
        contour: Contour
        contour.points = make([dynamic]Point, plan.allocator)
        edge := edges[first]
        start_x, start_z := edge.ax, edge.az
        current_x, current_z := start_x, start_z
        cursor := first
        for _ in 0 ..< len(edges) + 1 {
            if used[cursor] do break
            used[cursor] = true
            edge = edges[cursor]
            append(&contour.points, Point{f32(edge.ax), f32(edge.az)})
            current_x, current_z = edge.bx, edge.bz
            if current_x == start_x && current_z == start_z do break
            next := -1
            for candidate in 0 ..< len(edges) {
                if !used[candidate] && edge_equal_start(edges[candidate], current_x, current_z) {
                    next = candidate
                    break
                }
            }
            if next < 0 do break
            cursor = next
        }
        if len(contour.points) < 4 || current_x != start_x || current_z != start_z {
            delete(contour.points)
            continue
        }
        project_contour_to_bilinear_isoline(plan, &contour)
        round_contour(plan, &contour)
        for i in 0 ..< len(contour.points) {
            a := contour.points[i]
            b := contour.points[(i + 1) % len(contour.points)]
            contour.area += a.x * b.z - b.x * a.z
        }
        contour.area *= .5
        sample := contour.points[0]
        sample_x := clamp(int(sample.x), 0, GRID_WIDTH - 1)
        sample_z := clamp(int(sample.z), 0, GRID_HEIGHT - 1)
        component := int(labels[index_of(sample_x, sample_z)])
        if contour.area < 0 {
            contour.kind = .Lake
        } else if component == main_component {
            contour.kind = .Main_Coast
        } else {
            contour.kind = .Skerry
        }
        append(&plan.contours, contour)
    }
}

evaluate :: proc(plan: ^Plan) {
    labels: [CELL_COUNT]i16
    sizes: [256]int
    components := component_labels(plan.cleaned, true, labels[:], &sizes)
    main := 0
    for component in 1 ..< components {
        if sizes[component] > sizes[main] do main = component
    }
    water_labels: [CELL_COUNT]i16
    water_sizes: [256]int
    water_components := component_labels(plan.cleaned, false, water_labels[:], &water_sizes)
    ocean_component := int(water_labels[0])
    plan.bounds = {GRID_WIDTH, GRID_HEIGHT, 0, 0}
    d := &plan.diagnostics
    d.component_count = components
    d.main_land_cells = components > 0 ? sizes[main] : 0
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            index := index_of(x, z)
            if plan.cleaned[index] == .Land {
                d.land_cells += 1
                plan.bounds.min_x = min(plan.bounds.min_x, x)
                plan.bounds.min_z = min(plan.bounds.min_z, z)
                plan.bounds.max_x = max(plan.bounds.max_x, x)
                plan.bounds.max_z = max(plan.bounds.max_z, z)
                if x == 0 || z == 0 || x == GRID_WIDTH - 1 || z == GRID_HEIGHT - 1 do d.border_land_cells += 1
                cardinal := 0
                if is_land(plan.cleaned, x - 1, z) do cardinal += 1
                if is_land(plan.cleaned, x + 1, z) do cardinal += 1
                if is_land(plan.cleaned, x, z - 1) do cardinal += 1
                if is_land(plan.cleaned, x, z + 1) do cardinal += 1
                d.coastline_edges += 4 - cardinal
                if cardinal <= 2 do d.narrow_neck_cells += 1
            } else {
                d.water_cells += 1
                component := int(water_labels[index])
                if component != ocean_component && component >= 0 && water_sizes[component] >= 4 {
                    // Count once, at the first labeled cell.
                    first := true
                    for earlier in 0 ..< index {
                        if water_labels[earlier] == water_labels[index] {
                            first = false
                            break
                        }
                    }
                    if first do d.lake_count += 1
                }
            }
        }
    }
    for component in 0 ..< components {
        if component != main && sizes[component] >= MIN_SKERRY_CELLS do d.skerry_count += 1
    }
    d.coastline_complexity = f32(d.coastline_edges) / f32(max(d.land_cells, 1))
    bounds_width := max(f32(plan.bounds.max_x - plan.bounds.min_x + 1), f32(1))
    bounds_height := max(f32(plan.bounds.max_z - plan.bounds.min_z + 1), f32(1))
    d.aspect_ratio = max(bounds_width, bounds_height) / min(bounds_width, bounds_height)
    d.rectangularity = f32(d.main_land_cells) / max(bounds_width * bounds_height, f32(1))
    append_contours(plan, main, labels[:])
    if d.land_cells < 1250 || d.land_cells > 3600 do d.rejection_mask |= REJECT_AREA
    if d.border_land_cells > 0 do d.rejection_mask |= REJECT_BORDER
    if d.component_count > 8 do d.rejection_mask |= REJECT_FRAGMENTATION
    if d.narrow_neck_cells > d.land_cells / 10 do d.rejection_mask |= REJECT_NECKS
    if len(plan.contours) == 0 do d.rejection_mask |= REJECT_CONTOURS
    area_target := 2300
    area_score := 1 - min(f32(math.abs(d.land_cells - area_target)) / f32(area_target), f32(1))
    complexity_score := 1 - min(math.abs(d.coastline_complexity - .17) / .17, f32(1))
    aspect_target: f32
    switch plan.shape {
    case .Dinaric_Ridge:
        aspect_target = 3.1
    case .Forked_Ridge:
        aspect_target = 2.2
    case .Embayed_Plateau:
        aspect_target = 1.55
    case .Twin_Lobed:
        aspect_target = 1.75
    case .Broken_Ridge:
        aspect_target = 2.8
    }
    aspect_score := 1 - min(math.abs(d.aspect_ratio - aspect_target) / aspect_target, f32(1))
    rectangularity_score := 1 - clamp((d.rectangularity - .60) / .22, 0, 1)
    // Lakes and skerries are reported, but neither is rewarded merely for
    // existing. Candidate selection should not turn optional topology into an
    // implicit requirement.
    penalty := f32(d.border_land_cells) * .02 + f32(max(d.component_count - 5, 0)) * .05
    plan.score = area_score * .38 + complexity_score * .25 + aspect_score * .27 + rectangularity_score * .10 - penalty
    plan.valid = d.rejection_mask == 0
}

generate_candidate :: proc(seed: u32, allocator: runtime.Allocator) -> Plan {
    plan: Plan
    plan.allocator = allocator
    plan.selected_seed = seed
    plan.source = make([]Cell, CELL_COUNT, allocator)
    plan.cleaned = make([]Cell, CELL_COUNT, allocator)
    plan.signed_distance = make([]f32, CELL_COUNT, allocator)
    plan.elevation = make([]f32, CELL_COUNT, allocator)
    plan.bluff = make([]f32, CELL_COUNT, allocator)
    plan.contours = make([dynamic]Contour, allocator)
    if !run_markov(seed, plan.source) {
        plan.diagnostics.rejection_mask = REJECT_CONTOURS
        plan.score = -1e6
        return plan
    }
    plan.shape = shape_source(plan.source, seed)
    cleanup(plan.source, plan.cleaned)
    build_signed_distance(plan.cleaned, plan.signed_distance)
    build_vertical_form(&plan, seed)
    build_foliage(&plan, seed)
    evaluate(&plan)
    return plan
}

generate :: proc(requested_seed: u32, allocator := context.allocator) -> Plan {
    best: Plan
    best.score = -1e30
    valid_candidates := 0
    attempts := 0
    for attempt in 0 ..< MAX_CANDIDATE_ATTEMPTS {
        attempts = attempt + 1
        seed := requested_seed + u32(attempt) * 0x9e3779b9
        candidate := generate_candidate(seed, allocator)
        candidate.requested_seed = requested_seed
        candidate.attempts = attempt + 1
        if candidate.valid do valid_candidates += 1
        candidate_is_better :=
            (candidate.valid && !best.valid) || (candidate.valid == best.valid && candidate.score > best.score)
        if candidate_is_better {
            destroy(&best)
            best = candidate
        } else {
            destroy(&candidate)
        }
        if valid_candidates >= VALID_CANDIDATES_REQUIRED do break
    }
    best.attempts = attempts
    return best
}

sample_signed_distance :: proc(plan: ^Plan, normalized_x, normalized_z: f32) -> f32 {
    if plan == nil || len(plan.signed_distance) != CELL_COUNT do return 1e6
    raw_gx := (normalized_x * .5 + .5) * f32(GRID_WIDTH - 1)
    raw_gz := (normalized_z * .5 + .5) * f32(GRID_HEIGHT - 1)
    gx := clamp(raw_gx, f32(0), f32(GRID_WIDTH - 1))
    gz := clamp(raw_gz, f32(0), f32(GRID_HEIGHT - 1))
    x1, z1 := int(gx), int(gz)
    tx, tz := gx - f32(x1), gz - f32(z1)
    rows: [4]f32
    for row in 0 ..< 4 {
        z := clamp(z1 + row - 1, 0, GRID_HEIGHT - 1)
        rows[row] = sample_cubic(
            plan.signed_distance[index_of(clamp(x1 - 1, 0, GRID_WIDTH - 1), z)],
            plan.signed_distance[index_of(x1, z)],
            plan.signed_distance[index_of(clamp(x1 + 1, 0, GRID_WIDTH - 1), z)],
            plan.signed_distance[index_of(clamp(x1 + 2, 0, GRID_WIDTH - 1), z)],
            tx,
        )
    }
    sampled := sample_cubic(rows[0], rows[1], rows[2], rows[3], tz)
    // The generated field only covers the silhouette grid. Continue its
    // positive (water-side) distance beyond that grid so callers can form a
    // continuous seabed instead of clamping the whole outer world to the
    // distance stored in the border cells.
    outside_x := raw_gx - gx
    outside_z := raw_gz - gz
    if outside_x != 0 || outside_z != 0 {
        sampled += f32(math.sqrt(f64(outside_x * outside_x + outside_z * outside_z)))
    }
    return sampled
}

sample_field :: proc(field: []f32, normalized_x, normalized_z: f32) -> f32 {
    if len(field) != CELL_COUNT do return 0
    gx := clamp((normalized_x * .5 + .5) * f32(GRID_WIDTH - 1), f32(0), f32(GRID_WIDTH - 1))
    gz := clamp((normalized_z * .5 + .5) * f32(GRID_HEIGHT - 1), f32(0), f32(GRID_HEIGHT - 1))
    x0, z0 := int(gx), int(gz)
    x1, z1 := min(x0 + 1, GRID_WIDTH - 1), min(z0 + 1, GRID_HEIGHT - 1)
    tx, tz := gx - f32(x0), gz - f32(z0)
    a := field[index_of(x0, z0)]
    b := field[index_of(x1, z0)]
    c := field[index_of(x0, z1)]
    d := field[index_of(x1, z1)]
    top, bottom := a + (b - a) * tx, c + (d - c) * tx
    return top + (bottom - top) * tz
}

sample_cubic :: #force_inline proc(a, b, c, d, t: f32) -> f32 {
    // Catmull-Rom interpolation passes through the two central samples while
    // matching their neighboring slopes, removing the planar patches produced
    // by bilinear height interpolation.
    return b + .5 * t * (c - a + t * (2 * a - 5 * b + 4 * c - d + t * (3 * (b - c) + d - a)))
}

sample_field_bicubic :: proc(field: []f32, normalized_x, normalized_z: f32) -> f32 {
    if len(field) != CELL_COUNT do return 0
    gx := clamp((normalized_x * .5 + .5) * f32(GRID_WIDTH - 1), f32(0), f32(GRID_WIDTH - 1))
    gz := clamp((normalized_z * .5 + .5) * f32(GRID_HEIGHT - 1), f32(0), f32(GRID_HEIGHT - 1))
    x1, z1 := int(gx), int(gz)
    tx, tz := gx - f32(x1), gz - f32(z1)
    rows: [4]f32
    for row in 0 ..< 4 {
        z := clamp(z1 + row - 1, 0, GRID_HEIGHT - 1)
        x0 := clamp(x1 - 1, 0, GRID_WIDTH - 1)
        x2 := clamp(x1 + 1, 0, GRID_WIDTH - 1)
        x3 := clamp(x1 + 2, 0, GRID_WIDTH - 1)
        rows[row] = sample_cubic(
            field[index_of(x0, z)],
            field[index_of(x1, z)],
            field[index_of(x2, z)],
            field[index_of(x3, z)],
            tx,
        )
    }
    return sample_cubic(rows[0], rows[1], rows[2], rows[3], tz)
}

sample_elevation :: proc(plan: ^Plan, normalized_x, normalized_z: f32) -> f32 {
    if plan == nil do return 0
    return max(sample_field_bicubic(plan.elevation, normalized_x, normalized_z), f32(0))
}

sample_bluff :: proc(plan: ^Plan, normalized_x, normalized_z: f32) -> f32 {
    if plan == nil do return 0
    return sample_field(plan.bluff, normalized_x, normalized_z)
}
