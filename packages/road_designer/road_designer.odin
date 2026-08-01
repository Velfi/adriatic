package road_designer

import road_planner "../road_planner"
import roads "../roads"
import "core:math"

POPULATION_SIZE :: 48
MAX_GENOME_POINTS :: 14
MAX_CENTERLINE_POINTS :: 512
MAX_HORIZONTAL_ELEMENTS :: 40
MAX_VERTICAL_ELEMENTS :: 64
MAX_STRUCTURE_SPANS :: 16
MAX_EARTHWORK_SAMPLES :: MAX_CENTERLINE_POINTS
MAX_MATERIALIZED_POINTS :: 2 + 12 + MAX_STRUCTURE_SPANS * 2
PROFILE_LEVEL_COUNT :: 25
MAX_GENERATIONS :: 80
STALL_GENERATIONS :: 10

Named_Alternative :: enum u8 {
    Recommended,
    Cheapest,
    Fastest,
    Lightest_Impact,
}

Optimizer_Status :: enum u8 {
    Idle,
    Running,
    Complete,
    Cancelled,
    No_Route,
    Capacity,
}

Feasibility :: enum u8 {
    Feasible,
    No_Route,
    Capacity,
    Geometry,
    Grade,
    Profile,
}

Horizontal_Element_Kind :: enum u8 {Tangent, Spiral, Arc}
Vertical_Element_Kind :: enum u8 {Tangent, Crest, Sag}
Structure_Kind :: enum u8 {At_Grade, Bridge, Culvert}

Surface_Policy :: struct {
    design_speed_kph:       f32,
    maximum_grade:          f32,
    preferred_grade:        f32,
    minimum_radius:         f32,
    sight_distance:         f32,
    minimum_spiral_length:  f32,
    maximum_superelevation: f32,
    switchbacks_allowed:    bool,
    bridge_cost_per_m:      f32,
    culvert_cost:           f32,
    construction_weight:    f32,
    travel_weight:          f32,
    impact_weight:          f32,
}

Design_Request :: struct {
    grid:                 road_planner.Grid,
    cell_size:            f32,
    start, finish:        road_planner.Point,
    pavement:             roads.Pavement,
    width, shoulder:      f32,
    sea_level:            f32,
    available_nodes:      int,
    available_edges:      int,
    seed:                 u32,
    fixed_start_heading:  [2]f32,
    fixed_finish_heading: [2]f32,
    has_start_heading:    bool,
    has_finish_heading:   bool,
}

Horizontal_Element :: struct {
    kind:                       Horizontal_Element_Kind,
    station_from, station_to:   f32,
    curvature_from, curvature_to:f32,
    source_pi:                  int,
}

Vertical_Element :: struct {
    kind:                     Vertical_Element_Kind,
    station_from, station_to: f32,
    a, b, c, d:               f32,
}

Structure_Span :: struct {
    kind:                     Structure_Kind,
    station_from, station_to: f32,
    deck_y, invert_y:         f32,
    width, clearance:         f32,
}

Earthwork_Sample :: struct {
    station:                         f32,
    existing_y, finished_y:          f32,
    cut_area, fill_area:             f32,
    cumulative_cut, cumulative_fill: f32,
    haul_balance:                    f32,
}

Metrics :: struct {
    construction, travel, impact: f32,
    length, travel_seconds:       f32,
    cut_volume, fill_volume:      f32,
    haul, disturbed_area:         f32,
    maximum_grade:                f32,
    minimum_radius:               f32,
    bridge_length:                f32,
    culvert_count, switchbacks:   int,
}

Genome :: struct {
    points:      [MAX_GENOME_POINTS]road_planner.Point,
    radii:       [MAX_GENOME_POINTS]f32,
    spirals:     [MAX_GENOME_POINTS]f32,
    point_count: int,
}

Design_Candidate :: struct {
    id:          u64,
    genome:      Genome,
    centerline:  [MAX_CENTERLINE_POINTS]roads.Vec3,
    stations:    [MAX_CENTERLINE_POINTS]f32,
    point_count: int,
    horizontal:  [MAX_HORIZONTAL_ELEMENTS]Horizontal_Element,
    horizontal_count: int,
    vertical:    [MAX_VERTICAL_ELEMENTS]Vertical_Element,
    vertical_count: int,
    structures:  [MAX_STRUCTURE_SPANS]Structure_Span,
    structure_count: int,
    earthwork:   [MAX_EARTHWORK_SAMPLES]Earthwork_Sample,
    earthwork_count: int,
    metrics:     Metrics,
    feasibility: Feasibility,
    pareto_rank: int,
    crowding:    f32,
    pavement:    roads.Pavement,
    width, shoulder: f32,
}

Workspace :: struct {
    planner:       road_planner.Workspace,
    profile_cost:  [MAX_CENTERLINE_POINTS][PROFILE_LEVEL_COUNT]f32,
    profile_parent:[MAX_CENTERLINE_POINTS][PROFILE_LEVEL_COUNT]i8,
    merge:         [POPULATION_SIZE]Design_Candidate,
    combined:      [POPULATION_SIZE * 2]Design_Candidate,
}

Optimizer :: struct {
    request:       Design_Request,
    policy:        Surface_Policy,
    workspace:     ^Workspace,
    seed_route:    road_planner.Result,
    population:    [POPULATION_SIZE]Design_Candidate,
    offspring:     [POPULATION_SIZE]Design_Candidate,
    status:        Optimizer_Status,
    generation:    int,
    evaluations:   int,
    evaluation_cursor: int,
    stall_generations: int,
    best_signature: f32,
    rng:            u32,
    selected:       [4]int,
}

Materialize_Result :: struct {
    first_edge: int,
    edge_count: int,
    ok:         bool,
}

policy_for_pavement :: proc(pavement: roads.Pavement) -> Surface_Policy {
    policy := Surface_Policy {
        design_speed_kph = 25,
        maximum_grade = .20,
        minimum_radius = 14,
        sight_distance = 15,
        minimum_spiral_length = 6,
        maximum_superelevation = .03,
        switchbacks_allowed = true,
        bridge_cost_per_m = 18,
        culvert_cost = 90,
        construction_weight = .45,
        travel_weight = .30,
        impact_weight = .25,
    }
    switch pavement {
    case .Asphalt:
        policy.design_speed_kph, policy.maximum_grade = 60, .10
        policy.minimum_radius, policy.sight_distance = 70, 45
        policy.minimum_spiral_length, policy.maximum_superelevation = 18, .06
        policy.switchbacks_allowed = false
    case .Gravel:
        policy.design_speed_kph, policy.maximum_grade = 40, .14
        policy.minimum_radius, policy.sight_distance = 32, 28
        policy.minimum_spiral_length, policy.maximum_superelevation = 12, .04
    case .Cobblestone:
        policy.design_speed_kph, policy.maximum_grade = 30, .16
        policy.minimum_radius, policy.sight_distance = 20, 20
        policy.minimum_spiral_length, policy.maximum_superelevation = 8, .03
    case .Dirt:
    case .Steps:
        policy.maximum_grade = 0
    }
    policy.preferred_grade = policy.maximum_grade * .7
    return policy
}

hash :: #force_inline proc(value: u32) -> u32 {
    result := value
    result = result ~ (result >> 16)
    result *= 0x7feb352d
    result = result ~ (result >> 15)
    result *= 0x846ca68b
    return result ~ (result >> 16)
}

random_unit :: #force_inline proc(optimizer: ^Optimizer) -> f32 {
    optimizer.rng = hash(optimizer.rng + 0x9e3779b9)
    return f32(optimizer.rng & 0x00ffffff) / f32(0x01000000)
}

sample_height :: #force_inline proc(request: Design_Request, x, z: f32) -> f32 {
    grid := request.grid
    if grid.width <= 0 || grid.height <= 0 || len(grid.heights) < grid.width * grid.height do return request.sea_level
    cell := max(request.cell_size, f32(.001))
    fx := clamp((x - grid.origin_x) / cell, f32(0), f32(grid.width - 1))
    fz := clamp((z - grid.origin_z) / cell, f32(0), f32(grid.height - 1))
    x0, z0 := int(math.floor(f64(fx))), int(math.floor(f64(fz)))
    x1, z1 := min(x0 + 1, grid.width - 1), min(z0 + 1, grid.height - 1)
    tx, tz := fx - f32(x0), fz - f32(z0)
    a := grid.heights[z0 * grid.width + x0]
    b := grid.heights[z0 * grid.width + x1]
    c := grid.heights[z1 * grid.width + x0]
    d := grid.heights[z1 * grid.width + x1]
    return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * tz
}

distance :: #force_inline proc(a, b: road_planner.Point) -> f32 {
    dx, dz := b.x - a.x, b.z - a.z
    return f32(math.sqrt(f64(dx * dx + dz * dz)))
}

orientation :: #force_inline proc(a, b, c: roads.Vec3) -> f32 {
    return (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
}

segments_intersect :: proc(a, b, c, d: roads.Vec3) -> bool {
    ab_c, ab_d := orientation(a, b, c), orientation(a, b, d)
    cd_a, cd_b := orientation(c, d, a), orientation(c, d, b)
    return ((ab_c > .001 && ab_d < -.001) || (ab_c < -.001 && ab_d > .001)) &&
        ((cd_a > .001 && cd_b < -.001) || (cd_a < -.001 && cd_b > .001))
}

horizontal_constraints_hold :: proc(candidate: ^Design_Candidate, request: Design_Request, policy: Surface_Policy) -> bool {
    if candidate == nil || candidate.point_count < 2 do return false
    tolerance := f32(.01)
    if candidate.metrics.minimum_radius + tolerance < policy.minimum_radius do return false
    for index in 0 ..< candidate.genome.point_count {
        if index > 0 && index < candidate.genome.point_count - 1 &&
           (candidate.genome.radii[index] < policy.minimum_radius ||
            candidate.genome.spirals[index] < policy.minimum_spiral_length) {
            return false
        }
    }
    for first in 0 ..< candidate.point_count - 1 {
        for second in first + 2 ..< candidate.point_count - 1 {
            if second == first + 1 do continue
            if segments_intersect(candidate.centerline[first], candidate.centerline[first + 1],
                                  candidate.centerline[second], candidate.centerline[second + 1]) {
                return false
            }
        }
    }
    if request.has_start_heading {
        delta := candidate.centerline[1] - candidate.centerline[0]
        length := max(f32(math.sqrt(f64(delta.x * delta.x + delta.z * delta.z))), f32(.001))
        if delta.x / length * request.fixed_start_heading[0] + delta.z / length * request.fixed_start_heading[1] < .985 do return false
    }
    if request.has_finish_heading {
        last := candidate.point_count - 1
        delta := candidate.centerline[last] - candidate.centerline[last - 1]
        length := max(f32(math.sqrt(f64(delta.x * delta.x + delta.z * delta.z))), f32(.001))
        if delta.x / length * request.fixed_finish_heading[0] + delta.z / length * request.fixed_finish_heading[1] < .985 do return false
    }
    return true
}

materialized_segment_count :: proc(candidate: ^Design_Candidate) -> int {
    if candidate == nil || candidate.point_count < 2 do return 0
    count := clamp(candidate.genome.point_count - 1, 1, 12) + 1
    total := candidate.stations[candidate.point_count - 1]
    values: [MAX_MATERIALIZED_POINTS]f32
    nominal := count - 1
    for index in 0 ..< count do values[index] = total * f32(index) / f32(nominal)
    for span in candidate.structures[:candidate.structure_count] {
        span_boundaries := [2]f32{span.station_from, span.station_to}
        for boundary in span_boundaries {
            value := clamp(boundary, f32(0), total)
            duplicate := false
            for existing in values[:count] do if math.abs(existing - value) < .01 do duplicate = true
            if !duplicate && count < len(values) {
                values[count] = value
                count += 1
            }
        }
    }
    return count - 1
}

route_to_genome :: proc(route: ^road_planner.Result, policy: Surface_Policy) -> Genome {
    genome: Genome
    if route == nil || !route.found || route.point_count < 2 do return genome
    genome.points[0] = route.points[0]
    genome.point_count = 1
    for index in 1 ..< route.point_count - 1 {
        before, point, after := route.points[index - 1], route.points[index], route.points[index + 1]
        if point.x - before.x == after.x - point.x && point.z - before.z == after.z - point.z do continue
        if genome.point_count >= MAX_GENOME_POINTS - 1 do break
        genome.points[genome.point_count] = point
        genome.radii[genome.point_count] = policy.minimum_radius
        genome.spirals[genome.point_count] = policy.minimum_spiral_length
        genome.point_count += 1
    }
    genome.points[genome.point_count] = route.points[route.point_count - 1]
    genome.point_count += 1
    // Uniformly thin an over-detailed raster path while preserving terminals.
    if genome.point_count == MAX_GENOME_POINTS {
        thinned: Genome
        thinned.points[0] = genome.points[0]
        thinned.point_count = 1
        interior := min(10, genome.point_count - 2)
        for out_index in 0 ..< interior {
            source := 1 + (out_index * (genome.point_count - 2)) / max(interior, 1)
            thinned.points[thinned.point_count] = genome.points[source]
            thinned.radii[thinned.point_count] = policy.minimum_radius
            thinned.spirals[thinned.point_count] = policy.minimum_spiral_length
            thinned.point_count += 1
        }
        thinned.points[thinned.point_count] = genome.points[genome.point_count - 1]
        thinned.point_count += 1
        genome = thinned
    }
    return genome
}

mutate :: proc(optimizer: ^Optimizer, source: Genome, amount: f32) -> Genome {
    result := source
    if result.point_count <= 2 do return result
    span := distance(optimizer.request.start, optimizer.request.finish)
    tube := max(optimizer.request.cell_size * 4, span * .12)
    for index in 1 ..< result.point_count - 1 {
        if random_unit(optimizer) > .42 do continue
        previous, next := result.points[index - 1], result.points[index + 1]
        dx, dz := next.x - previous.x, next.z - previous.z
        length := max(f32(math.sqrt(f64(dx * dx + dz * dz))), f32(.001))
        side_x, side_z := -dz / length, dx / length
        along := (random_unit(optimizer) * 2 - 1) * tube * .18 * amount
        lateral := (random_unit(optimizer) * 2 - 1) * tube * .34 * amount
        result.points[index].x += dx / length * along + side_x * lateral
        result.points[index].z += dz / length * along + side_z * lateral
        result.radii[index] = max(
            optimizer.policy.minimum_radius,
            result.radii[index] * (.82 + random_unit(optimizer) * .42),
        )
        result.spirals[index] = max(
            optimizer.policy.minimum_spiral_length,
            result.spirals[index] * (.82 + random_unit(optimizer) * .38),
        )
    }
    return result
}

build_centerline :: proc(candidate: ^Design_Candidate, request: Design_Request, policy: Surface_Policy) -> bool {
    genome := &candidate.genome
    candidate.point_count = 0
    candidate.horizontal_count = 0
    if genome.point_count < 2 do return false
    candidate.pavement, candidate.width, candidate.shoulder = request.pavement, request.width, request.shoulder
    // Two Chaikin passes remove raster corners before four-metre stationing.
    smooth_a, smooth_b: [MAX_GENOME_POINTS * 4]road_planner.Point
    smooth_count := genome.point_count
    copy(smooth_a[:smooth_count], genome.points[:smooth_count])
    for pass in 0 ..< 2 {
        next_count := 0
        smooth_b[next_count] = smooth_a[0]
        next_count += 1
        for index in 0 ..< smooth_count - 1 {
            a, b := smooth_a[index], smooth_a[index + 1]
            if index > 0 {
                smooth_b[next_count] = {a.x * .75 + b.x * .25, a.z * .75 + b.z * .25}
                next_count += 1
            }
            if index < smooth_count - 2 {
                smooth_b[next_count] = {a.x * .25 + b.x * .75, a.z * .25 + b.z * .75}
                next_count += 1
            }
        }
        smooth_b[next_count] = smooth_a[smooth_count - 1]
        next_count += 1
        copy(smooth_a[:next_count], smooth_b[:next_count])
        smooth_count = next_count
    }
    station: f32
    for segment in 0 ..< smooth_count - 1 {
        a, b := smooth_a[segment], smooth_a[segment + 1]
        segment_length := distance(a, b)
        divisions := max(int(math.ceil(f64(segment_length / 4))), 1)
        for division in 0 ..< divisions {
            if candidate.point_count >= MAX_CENTERLINE_POINTS - 1 do return false
            t := f32(division) / f32(divisions)
            x, z := a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t
            if candidate.point_count > 0 {
                previous := candidate.centerline[candidate.point_count - 1]
                dx, dz := x - previous.x, z - previous.z
                station += f32(math.sqrt(f64(dx * dx + dz * dz)))
            }
            candidate.centerline[candidate.point_count] = {x, sample_height(request, x, z), z}
            candidate.stations[candidate.point_count] = station
            candidate.point_count += 1
        }
    }
    finish := smooth_a[smooth_count - 1]
    if candidate.point_count > 0 {
        previous := candidate.centerline[candidate.point_count - 1]
        dx, dz := finish.x - previous.x, finish.z - previous.z
        station += f32(math.sqrt(f64(dx * dx + dz * dz)))
    }
    candidate.centerline[candidate.point_count] = {finish.x, sample_height(request, finish.x, finish.z), finish.z}
    candidate.stations[candidate.point_count] = station
    candidate.point_count += 1
    // Persist an engineering element vocabulary even though the render graph
    // consumes a cubic approximation after materialization.
    for pi in 0 ..< genome.point_count - 1 {
        if candidate.horizontal_count >= MAX_HORIZONTAL_ELEMENTS do return false
        from := pi == 0 ? f32(0) : candidate.stations[min(pi * (candidate.point_count - 1) / (genome.point_count - 1), candidate.point_count - 1)]
        to := pi == genome.point_count - 2 ? station : candidate.stations[min((pi + 1) * (candidate.point_count - 1) / (genome.point_count - 1), candidate.point_count - 1)]
        kind := Horizontal_Element_Kind.Tangent
        curvature_from, curvature_to := f32(0), f32(0)
        if pi > 0 && pi < genome.point_count - 1 {
            kind = .Spiral
            curvature_to = 1 / max(genome.radii[pi], policy.minimum_radius)
        }
        candidate.horizontal[candidate.horizontal_count] = {kind, from, to, curvature_from, curvature_to, pi}
        candidate.horizontal_count += 1
    }
    return true
}

solve_profile :: proc(candidate: ^Design_Candidate, request: Design_Request, policy: Surface_Policy, work: ^Workspace) -> bool {
    count := candidate.point_count
    if count < 2 || work == nil do return false
    infinity := f32(1e30)
    step := f32(1)
    half := PROFILE_LEVEL_COUNT / 2
    start_y := candidate.centerline[0].y
    finish_y := candidate.centerline[count - 1].y
    total := max(candidate.stations[count - 1], f32(.001))
    for station_index in 0 ..< count {
        for level in 0 ..< PROFILE_LEVEL_COUNT {
            work.profile_cost[station_index][level] = infinity
            work.profile_parent[station_index][level] = -1
        }
    }
    work.profile_cost[0][half] = 0
    for station_index in 1 ..< count {
        station := candidate.stations[station_index]
        baseline := start_y + (finish_y - start_y) * station / total
        previous_station := candidate.stations[station_index - 1]
        previous_baseline := start_y + (finish_y - start_y) * previous_station / total
        ds := max(station - previous_station, f32(.001))
        for level in 0 ..< PROFILE_LEVEL_COUNT {
            if station_index == count - 1 && level != half do continue
            y := baseline + f32(level - half) * step
            ground := candidate.centerline[station_index].y
            local_earthwork := math.abs(y - ground) * (request.width + request.shoulder * 2)
            for previous_level in 0 ..< PROFILE_LEVEL_COUNT {
                previous_cost := work.profile_cost[station_index - 1][previous_level]
                if previous_cost >= infinity do continue
                previous_y := previous_baseline + f32(previous_level - half) * step
                grade := math.abs((y - previous_y) / ds)
                if grade > policy.maximum_grade + .0001 do continue
                grade_penalty := max(grade - policy.preferred_grade, f32(0)) * ds * 42
                cost := previous_cost + local_earthwork * ds + grade_penalty
                if cost < work.profile_cost[station_index][level] {
                    work.profile_cost[station_index][level] = cost
                    work.profile_parent[station_index][level] = i8(previous_level)
                }
            }
        }
    }
    if work.profile_cost[count - 1][half] >= infinity do return false
    level := half
    for reverse in 0 ..< count {
        index := count - 1 - reverse
        baseline := start_y + (finish_y - start_y) * candidate.stations[index] / total
        candidate.centerline[index].y = baseline + f32(level - half) * step
        if index > 0 {
            parent := int(work.profile_parent[index][level])
            if parent < 0 do return false
            level = parent
        }
    }
    candidate.vertical_count = 0
    for index in 0 ..< count - 1 {
        if candidate.vertical_count >= MAX_VERTICAL_ELEMENTS do break
        ds := max(candidate.stations[index + 1] - candidate.stations[index], f32(.001))
        grade := (candidate.centerline[index + 1].y - candidate.centerline[index].y) / ds
        kind := Vertical_Element_Kind.Tangent
        if index > 0 {
            previous_ds := max(candidate.stations[index] - candidate.stations[index - 1], f32(.001))
            previous_grade := (candidate.centerline[index].y - candidate.centerline[index - 1].y) / previous_ds
            if grade > previous_grade + .002 do kind = .Sag
            if grade < previous_grade - .002 do kind = .Crest
        }
        candidate.vertical[candidate.vertical_count] = {
            kind = kind,
            station_from = candidate.stations[index],
            station_to = candidate.stations[index + 1],
            a = candidate.centerline[index].y,
            b = grade,
        }
        candidate.vertical_count += 1
    }
    return true
}

evaluate :: proc(candidate: ^Design_Candidate, request: Design_Request, policy: Surface_Policy, work: ^Workspace) -> Metrics {
    metrics: Metrics
    candidate.feasibility = .Geometry
    if !build_centerline(candidate, request, policy) do return metrics
    if !solve_profile(candidate, request, policy, work) {
        candidate.feasibility = .Profile
        return metrics
    }
    candidate.structure_count = 0
    candidate.earthwork_count = candidate.point_count
    metrics.minimum_radius = f32(1e30)
    cumulative_cut, cumulative_fill: f32
    open_water := false
    water_start := f32(0)
    for index in 0 ..< candidate.point_count {
        point := candidate.centerline[index]
        station := candidate.stations[index]
        ground := sample_height(request, point.x, point.z)
        ds := index == 0 ? f32(0) : station - candidate.stations[index - 1]
        difference := point.y - ground
        cross_width := request.width + request.shoulder * 2 + math.abs(difference) * 4
        cut_area, fill_area := f32(0), f32(0)
        if difference < 0 do cut_area = -difference * cross_width
        if difference > 0 do fill_area = difference * cross_width
        cumulative_cut += cut_area * ds
        cumulative_fill += fill_area * ds
        metrics.haul += math.abs(cumulative_cut - cumulative_fill) * ds
        candidate.earthwork[index] = {
            station = station,
            existing_y = ground,
            finished_y = point.y,
            cut_area = cut_area,
            fill_area = fill_area,
            cumulative_cut = cumulative_cut,
            cumulative_fill = cumulative_fill,
            haul_balance = cumulative_cut - cumulative_fill,
        }
        wet := ground <= request.sea_level + .04
        if wet && !open_water {
            open_water, water_start = true, station
        }
        if open_water && (!wet || index == candidate.point_count - 1) {
            water_end := station
            span_length := max(water_end - water_start, ds)
            if candidate.structure_count < MAX_STRUCTURE_SPANS {
                kind := span_length <= 14 && difference <= 3 ? Structure_Kind.Culvert : .Bridge
                candidate.structures[candidate.structure_count] = {
                    kind = kind,
                    station_from = water_start,
                    station_to = water_end,
                    deck_y = point.y,
                    invert_y = ground,
                    width = request.width + request.shoulder * 2,
                    clearance = max(point.y - ground, f32(.8)),
                }
                candidate.structure_count += 1
                if kind == .Bridge {
                    metrics.bridge_length += span_length
                } else {
                    metrics.culvert_count += 1
                }
            }
            open_water = false
        }
        if index > 0 {
            previous := candidate.centerline[index - 1]
            grade := math.abs((point.y - previous.y) / max(ds, f32(.001)))
            metrics.maximum_grade = max(metrics.maximum_grade, grade)
        }
        if index > 0 && index < candidate.point_count - 1 {
            a, b, c := candidate.centerline[index - 1], point, candidate.centerline[index + 1]
            abx, abz := b.x - a.x, b.z - a.z
            bcx, bcz := c.x - b.x, c.z - b.z
            lab := max(f32(math.sqrt(f64(abx * abx + abz * abz))), f32(.001))
            lbc := max(f32(math.sqrt(f64(bcx * bcx + bcz * bcz))), f32(.001))
            dot := clamp((abx * bcx + abz * bcz) / (lab * lbc), f32(-1), f32(1))
            angle := f32(math.acos(f64(dot)))
            radius := angle <= .0001 ? f32(1e30) : min(lab, lbc) / (2 * math.sin(angle * .5))
            metrics.minimum_radius = min(metrics.minimum_radius, radius)
        }
    }
    metrics.length = candidate.stations[candidate.point_count - 1]
    metrics.cut_volume, metrics.fill_volume = cumulative_cut, cumulative_fill
    metrics.disturbed_area = metrics.length * (request.width + request.shoulder * 2) +
        (metrics.cut_volume + metrics.fill_volume) * .35
    speed_mps := max(policy.design_speed_kph / 3.6, f32(1))
    metrics.travel_seconds = metrics.length / speed_mps * (1 + metrics.maximum_grade * 2.2)
    imbalance := math.abs(metrics.cut_volume - metrics.fill_volume)
    metrics.construction = metrics.length + (metrics.cut_volume + metrics.fill_volume) * .18 +
        imbalance * .12 + metrics.haul * .0006 + metrics.bridge_length * policy.bridge_cost_per_m +
        f32(metrics.culvert_count) * policy.culvert_cost
    metrics.travel = metrics.travel_seconds + max(policy.minimum_radius - metrics.minimum_radius, f32(0)) * 3
    metrics.impact = metrics.disturbed_area + metrics.bridge_length * 12 + f32(metrics.culvert_count) * 30
    candidate.metrics = metrics
    required_segments := materialized_segment_count(candidate)
    if required_segments - 1 > request.available_nodes || required_segments > request.available_edges {
        candidate.feasibility = .Capacity
    } else if metrics.maximum_grade > policy.maximum_grade + .0001 {
        candidate.feasibility = .Grade
    } else if !horizontal_constraints_hold(candidate, request, policy) {
        candidate.feasibility = .Geometry
    } else {
        candidate.feasibility = .Feasible
    }
    return metrics
}

dominates :: #force_inline proc(a, b: ^Design_Candidate) -> bool {
    if a == nil || b == nil || a.feasibility != .Feasible do return false
    if b.feasibility != .Feasible do return true
    no_worse := a.metrics.construction <= b.metrics.construction && a.metrics.travel <= b.metrics.travel &&
        a.metrics.impact <= b.metrics.impact
    better := a.metrics.construction < b.metrics.construction || a.metrics.travel < b.metrics.travel ||
        a.metrics.impact < b.metrics.impact
    return no_worse && better
}

objective_value :: #force_inline proc(candidate: ^Design_Candidate, axis: int) -> f32 {
    switch axis {
    case 0: return candidate.metrics.construction
    case 1: return candidate.metrics.travel
    case 2: return candidate.metrics.impact
    }
    return 0
}

assign_fronts_and_crowding :: proc(items: []Design_Candidate) {
    for &item in items {
        item.pareto_rank = item.feasibility == .Feasible ? -1 : 1000
        item.crowding = 0
    }
    remaining := true
    rank := 0
    front_members: [POPULATION_SIZE * 2]bool
    for remaining {
        remaining = false
        assigned_this_front := false
        for &member in front_members do member = false
        for item, index in items {
            if item.pareto_rank != -1 do continue
            dominated_by_unassigned := false
            for &other, other_index in items {
                if other_index != index && other.pareto_rank == -1 && dominates(&other, &items[index]) {
                    dominated_by_unassigned = true
                    break
                }
            }
            if !dominated_by_unassigned {
                front_members[index] = true
                assigned_this_front = true
            }
        }
        for member, index in front_members do if member do items[index].pareto_rank = rank
        for item in items do if item.pareto_rank == -1 do remaining = true
        if !assigned_this_front && remaining do break
        rank += 1
    }
    indices: [POPULATION_SIZE * 2]int
    for front in 0 ..< rank {
        count := 0
        for item, index in items {
            if item.pareto_rank == front {
                indices[count] = index
                count += 1
            }
        }
        if count == 0 do continue
        if count <= 2 {
            for index in indices[:count] do items[index].crowding = f32(1e30)
            continue
        }
        for axis in 0 ..< 3 {
            for sorted in 0 ..< count - 1 {
                best := sorted
                for cursor in sorted + 1 ..< count {
                    if objective_value(&items[indices[cursor]], axis) < objective_value(&items[indices[best]], axis) do best = cursor
                }
                indices[sorted], indices[best] = indices[best], indices[sorted]
            }
            low := objective_value(&items[indices[0]], axis)
            high := objective_value(&items[indices[count - 1]], axis)
            items[indices[0]].crowding = f32(1e30)
            items[indices[count - 1]].crowding = f32(1e30)
            scale := max(high - low, f32(.001))
            for cursor in 1 ..< count - 1 {
                if items[indices[cursor]].crowding < f32(1e29) {
                    items[indices[cursor]].crowding +=
                        (objective_value(&items[indices[cursor + 1]], axis) -
                         objective_value(&items[indices[cursor - 1]], axis)) / scale
                }
            }
        }
    }
}

rank_and_select :: proc(optimizer: ^Optimizer) {
    assign_fronts_and_crowding(optimizer.population[:])
    choices := &[4]int{-1, -1, -1, -1}
    minimum, maximum := [3]f32{1e30, 1e30, 1e30}, [3]f32{-1e30, -1e30, -1e30}
    for &item in optimizer.population {
        if item.feasibility != .Feasible || item.pareto_rank != 0 do continue
        values := [3]f32{item.metrics.construction, item.metrics.travel, item.metrics.impact}
        for axis in 0 ..< 3 {
            minimum[axis] = min(minimum[axis], values[axis])
            maximum[axis] = max(maximum[axis], values[axis])
        }
    }
    best := [4]f32{1e30, 1e30, 1e30, 1e30}
    for &item, index in optimizer.population {
        if item.feasibility != .Feasible || item.pareto_rank != 0 do continue
        normalized: [3]f32
        values := [3]f32{item.metrics.construction, item.metrics.travel, item.metrics.impact}
        for axis in 0 ..< 3 do normalized[axis] = (values[axis] - minimum[axis]) / max(maximum[axis] - minimum[axis], f32(.001))
        scores := [4]f32{
            normalized[0] * optimizer.policy.construction_weight + normalized[1] * optimizer.policy.travel_weight + normalized[2] * optimizer.policy.impact_weight,
            normalized[0], normalized[1], normalized[2],
        }
        for choice in 0 ..< 4 {
            if scores[choice] < best[choice] || (scores[choice] == best[choice] &&
               (choices[choice] < 0 || item.id < optimizer.population[choices[choice]].id)) {
                best[choice], choices[choice] = scores[choice], index
            }
        }
    }
    optimizer.selected = choices^
}

candidate_precedes :: #force_inline proc(a, b: ^Design_Candidate) -> bool {
    if a.pareto_rank != b.pareto_rank do return a.pareto_rank < b.pareto_rank
    if a.crowding != b.crowding do return a.crowding > b.crowding
    return a.id < b.id
}

select_survivors :: proc(optimizer: ^Optimizer) {
    combined := &optimizer.workspace.combined
    for index in 0 ..< POPULATION_SIZE {
        combined[index] = optimizer.population[index]
        combined[POPULATION_SIZE + index] = optimizer.offspring[index]
    }
    assign_fronts_and_crowding(combined[:])
    chosen: [POPULATION_SIZE * 2]bool
    for output in 0 ..< POPULATION_SIZE {
        best := -1
        for index in 0 ..< len(combined) {
            if chosen[index] do continue
            if best < 0 || candidate_precedes(&combined[index], &combined[best]) do best = index
        }
        optimizer.workspace.merge[output] = combined[best]
        chosen[best] = true
    }
    optimizer.population = optimizer.workspace.merge
    rank_and_select(optimizer)
}

tournament :: proc(optimizer: ^Optimizer) -> int {
    a := int(random_unit(optimizer) * POPULATION_SIZE) % POPULATION_SIZE
    b := int(random_unit(optimizer) * POPULATION_SIZE) % POPULATION_SIZE
    return candidate_precedes(&optimizer.population[a], &optimizer.population[b]) ? a : b
}

crossover :: proc(optimizer: ^Optimizer, first, second: Genome) -> Genome {
    if first.point_count != second.point_count || first.point_count <= 3 do return first
    result := first
    begin_index := 1 + int(random_unit(optimizer) * f32(first.point_count - 2))
    end_index := begin_index + int(random_unit(optimizer) * f32(first.point_count - begin_index - 1))
    for index in begin_index ..= end_index {
        result.points[index] = second.points[index]
        result.radii[index] = second.radii[index]
        result.spirals[index] = second.spirals[index]
    }
    return result
}

begin :: proc(optimizer: ^Optimizer, request: Design_Request, workspace: ^Workspace) -> Optimizer_Status {
    if optimizer == nil || workspace == nil do return .No_Route
    optimizer^ = {}
    optimizer.request, optimizer.workspace = request, workspace
    optimizer.policy = policy_for_pavement(request.pavement)
    optimizer.rng = request.seed
    optimizer.selected = {-1, -1, -1, -1}
    if request.pavement == .Steps || optimizer.policy.maximum_grade <= 0 {
        optimizer.status = .No_Route
        return optimizer.status
    }
    if request.available_nodes < 2 || request.available_edges < 1 {
        optimizer.status = .Capacity
        return optimizer.status
    }
    config := road_planner.get_generation_config()
    config.cell_size = request.cell_size
    config.maximum_grade = optimizer.policy.maximum_grade
    optimizer.seed_route = road_planner.plan(&workspace.planner, request.grid, config, request.start, request.finish)
    if !optimizer.seed_route.found {
        optimizer.status = .No_Route
        return optimizer.status
    }
    seed_genome := route_to_genome(&optimizer.seed_route, optimizer.policy)
    if max(seed_genome.point_count - 2, 0) > request.available_nodes ||
       seed_genome.point_count - 1 > request.available_edges {
        optimizer.status = .Capacity
        return optimizer.status
    }
    for &item, index in optimizer.population {
        item = {}
        item.id = u64(index + 1)
        item.genome = index == 0 ? seed_genome : mutate(optimizer, seed_genome, f32(index) / POPULATION_SIZE)
        item.feasibility = .Geometry
    }
    // Evaluate the repaired A* seed synchronously so callers can display a
    // feasible corridor in the same frame that optimization begins.
    _ = evaluate(&optimizer.population[0], optimizer.request, optimizer.policy, optimizer.workspace)
    optimizer.evaluation_cursor = 1
    optimizer.evaluations = 1
    if optimizer.population[0].feasibility == .Feasible {
        optimizer.population[0].pareto_rank = 0
        optimizer.selected = {0, 0, 0, 0}
    }
    optimizer.status = .Running
    optimizer.best_signature = f32(1e30)
    return optimizer.status
}

step :: proc(optimizer: ^Optimizer, evaluation_budget: int = 8) -> Optimizer_Status {
    if optimizer == nil || optimizer.status != .Running do return optimizer == nil ? .Idle : optimizer.status
    budget := max(evaluation_budget, 1)
    for _ in 0 ..< budget {
        if optimizer.evaluation_cursor >= POPULATION_SIZE {
            if optimizer.generation > 0 {
                select_survivors(optimizer)
            } else {
                rank_and_select(optimizer)
            }
            recommended := optimizer.selected[int(Named_Alternative.Recommended)]
            signature := recommended >= 0 ? optimizer.population[recommended].metrics.construction +
                optimizer.population[recommended].metrics.travel + optimizer.population[recommended].metrics.impact : f32(1e30)
            if signature + .001 < optimizer.best_signature {
                optimizer.best_signature, optimizer.stall_generations = signature, 0
            } else {
                optimizer.stall_generations += 1
            }
            optimizer.generation += 1
            if optimizer.generation >= MAX_GENERATIONS || optimizer.stall_generations >= STALL_GENERATIONS {
                optimizer.status = .Complete
                return optimizer.status
            }
            for &item, index in optimizer.offspring {
                item = {}
                item.id = u64(optimizer.generation * POPULATION_SIZE + index + 1)
                first := optimizer.population[tournament(optimizer)].genome
                second := optimizer.population[tournament(optimizer)].genome
                child := crossover(optimizer, first, second)
                item.genome = mutate(optimizer, child, .45 + f32(index % 7) * .09)
                item.feasibility = .Geometry
            }
            optimizer.evaluation_cursor = 0
        }
        item := &optimizer.population[optimizer.evaluation_cursor]
        if optimizer.generation > 0 do item = &optimizer.offspring[optimizer.evaluation_cursor]
        _ = evaluate(item, optimizer.request, optimizer.policy, optimizer.workspace)
        optimizer.evaluation_cursor += 1
        optimizer.evaluations += 1
    }
    return optimizer.status
}

cancel :: proc(optimizer: ^Optimizer) {
    if optimizer == nil do return
    optimizer.status = .Cancelled
}

candidate :: proc(optimizer: ^Optimizer, alternative: Named_Alternative) -> (^Design_Candidate, bool) {
    if optimizer == nil do return nil, false
    index := optimizer.selected[int(alternative)]
    if index < 0 || index >= POPULATION_SIZE do return nil, false
    value := &optimizer.population[index]
    return value, value.feasibility == .Feasible
}

structure_at_station :: proc(candidate: ^Design_Candidate, station: f32) -> Structure_Kind {
    if candidate == nil do return .At_Grade
    for span in candidate.structures[:candidate.structure_count] {
        if station >= span.station_from && station <= span.station_to do return span.kind
    }
    return .At_Grade
}

alignment_at_station :: proc(candidate: ^Design_Candidate, station: f32) -> Horizontal_Element_Kind {
    if candidate == nil do return .Tangent
    for element in candidate.horizontal[:candidate.horizontal_count] {
        if station >= element.station_from && station <= element.station_to do return element.kind
    }
    return .Tangent
}

point_at_station :: proc(candidate: ^Design_Candidate, station: f32) -> roads.Vec3 {
    if candidate == nil || candidate.point_count <= 0 do return {}
    if station <= 0 do return candidate.centerline[0]
    last := candidate.point_count - 1
    if station >= candidate.stations[last] do return candidate.centerline[last]
    for index in 0 ..< last {
        if station > candidate.stations[index + 1] do continue
        span := max(candidate.stations[index + 1] - candidate.stations[index], f32(.001))
        t := clamp((station - candidate.stations[index]) / span, f32(0), f32(1))
        return candidate.centerline[index] + (candidate.centerline[index + 1] - candidate.centerline[index]) * t
    }
    return candidate.centerline[last]
}

materialize_between :: proc(
    candidate: ^Design_Candidate,
    graph: ^roads.Graph,
    design_id: u32,
    from, to: int,
) -> Materialize_Result {
    result := Materialize_Result{first_edge = -1}
    if candidate == nil || graph == nil || candidate.feasibility != .Feasible || candidate.point_count < 2 ||
       from < 0 || from >= graph.node_count || to < 0 || to >= graph.node_count || from == to {
        return result
    }
    total_station := candidate.stations[candidate.point_count - 1]
    nominal_segments := clamp(candidate.genome.point_count - 1, 1, 12)
    boundaries: [MAX_MATERIALIZED_POINTS]f32
    boundary_count := nominal_segments + 1
    for index in 0 ..< boundary_count do boundaries[index] = total_station * f32(index) / f32(nominal_segments)
    for span in candidate.structures[:candidate.structure_count] {
        span_boundaries := [2]f32{span.station_from, span.station_to}
        for boundary in span_boundaries {
            value := clamp(boundary, f32(0), total_station)
            duplicate := false
            for existing in boundaries[:boundary_count] {
                if math.abs(existing - value) < .01 do duplicate = true
            }
            if !duplicate && boundary_count < len(boundaries) {
                boundaries[boundary_count] = value
                boundary_count += 1
            }
        }
    }
    for index in 1 ..< boundary_count {
        value := boundaries[index]
        cursor := index
        for cursor > 0 && boundaries[cursor - 1] > value {
            boundaries[cursor] = boundaries[cursor - 1]
            cursor -= 1
        }
        boundaries[cursor] = value
    }
    segment_count := boundary_count - 1
    if graph.node_count + segment_count - 1 > roads.MAX_NODES || graph.edge_count + segment_count > roads.MAX_EDGES {
        return result
    }
    nodes: [MAX_MATERIALIZED_POINTS]int
    nodes[0], nodes[segment_count] = from, to
    points: [MAX_MATERIALIZED_POINTS]roads.Vec3
    points[0], points[segment_count] = candidate.centerline[0], candidate.centerline[candidate.point_count - 1]
    for segment in 1 ..< segment_count {
        points[segment] = point_at_station(candidate, boundaries[segment])
        nodes[segment] = roads.add_node(graph, points[segment], max(candidate.width * .8, f32(2)))
        if nodes[segment] < 0 do return result
    }
    result.first_edge = graph.edge_count
    for segment in 0 ..< segment_count {
        a, b := points[segment], points[segment + 1]
        before := segment > 0 ? points[segment - 1] : a
        after := segment + 2 <= segment_count ? points[segment + 2] : b
        from_tangent := b - before
        to_tangent := after - a
        from_length := max(math.sqrt(from_tangent.x * from_tangent.x + from_tangent.y * from_tangent.y + from_tangent.z * from_tangent.z), f32(.001))
        to_length := max(math.sqrt(to_tangent.x * to_tangent.x + to_tangent.y * to_tangent.y + to_tangent.z * to_tangent.z), f32(.001))
        from_tangent /= from_length
        to_tangent /= to_length
        length := math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) + (b.z - a.z) * (b.z - a.z))
        handle := length / 3
        edge_index := roads.add_edge(
            graph,
            nodes[segment],
            nodes[segment + 1],
            a + from_tangent * handle,
            b - to_tangent * handle,
            candidate.width,
            candidate.shoulder,
            candidate.pavement,
        )
        if edge_index < 0 do return result
        edge := &graph.edges[edge_index]
        station_from := boundaries[segment]
        station_to := boundaries[segment + 1]
        alignment := alignment_at_station(candidate, (station_from + station_to) * .5)
        edge.design_id = design_id
        edge.engineering_designed = true
        edge.authored_profile = true
        edge.policy_pavement = candidate.pavement
        edge.station_from, edge.station_to = station_from, station_to
        switch alignment {
        case .Tangent: edge.alignment_kind = .Tangent
        case .Spiral:  edge.alignment_kind = .Spiral
        case .Arc:     edge.alignment_kind = .Arc
        }
        horizontal := candidate.horizontal[min(segment * max(candidate.horizontal_count, 1) / segment_count, max(candidate.horizontal_count - 1, 0))]
        edge.curvature_from, edge.curvature_to = horizontal.curvature_from, horizontal.curvature_to
        edge.superelevation_from = clamp(edge.curvature_from * candidate.width * 2, -policy_for_pavement(candidate.pavement).maximum_superelevation, policy_for_pavement(candidate.pavement).maximum_superelevation)
        edge.superelevation_to = clamp(edge.curvature_to * candidate.width * 2, -policy_for_pavement(candidate.pavement).maximum_superelevation, policy_for_pavement(candidate.pavement).maximum_superelevation)
        switch structure_at_station(candidate, (station_from + station_to) * .5) {
        case .At_Grade: edge.structure_kind = .At_Grade
        case .Bridge:   edge.structure_kind = .Bridge
        case .Culvert:  edge.structure_kind = .Culvert
        }
        result.edge_count += 1
    }
    result.ok = result.edge_count == segment_count
    return result
}

materialize :: proc(candidate: ^Design_Candidate, graph: ^roads.Graph, design_id: u32) -> Materialize_Result {
    result := Materialize_Result{first_edge = -1}
    if candidate == nil || graph == nil || candidate.point_count < 2 do return result
    from := roads.add_node(graph, candidate.centerline[0], max(candidate.width * .8, f32(2)))
    to := roads.add_node(graph, candidate.centerline[candidate.point_count - 1], max(candidate.width * .8, f32(2)))
    if from < 0 || to < 0 do return result
    return materialize_between(candidate, graph, design_id, from, to)
}
