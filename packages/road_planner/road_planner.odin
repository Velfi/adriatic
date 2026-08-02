package road_planner

import "core:math"

MAX_GRID_WIDTH :: 128
MAX_GRID_HEIGHT :: 128
MAX_GRID_CELLS :: MAX_GRID_WIDTH * MAX_GRID_HEIGHT
MAX_DIRECTIONS :: 16
MAX_STATES :: MAX_GRID_CELLS * MAX_DIRECTIONS
MAX_PATH_POINTS :: MAX_GRID_CELLS

Point :: struct { x, z: f32 }

Config :: struct {
    cell_size:        f32,
    length_cost:      f32,
    grade_cost:       f32,
    steep_grade_cost: f32,
    water_cost:       f32,
    turn_cost:        f32,
    switchback_cost:  f32,
    maximum_grade:    f32,
    heuristic_weight: f32,
}

DEFAULT_CONFIG :: Config {
        cell_size        = 18,
        length_cost      = 1,
        grade_cost       = 34,
        steep_grade_cost = 180,
        water_cost       = 450,
        turn_cost        = 1.5,
        switchback_cost  = 18,
        maximum_grade    = .24,
        heuristic_weight = 1.08,
}

default_config :: proc() -> Config { return DEFAULT_CONFIG }

generation_config := DEFAULT_CONFIG

set_generation_config :: proc(config: Config) {
    generation_config = config
}

get_generation_config :: proc() -> Config {
    return generation_config
}

Grid :: struct {
    origin_x, origin_z: f32,
    width, height:      int,
    sea_level:          f32,
    heights:            []f32,
    // Optional product-supplied exclusion mask. Keeping obstacles in the grid
    // lets every caller use the same search without teaching the planner what
    // a runway, protected site, or other domain object means.
    blocked:            []bool,
}

Result :: struct {
    points:       [MAX_PATH_POINTS]Point,
    point_count:  int,
    total_cost:   f32,
    expanded:     int,
    found:        bool,
}

Workspace :: struct {
    scores:         [MAX_STATES]f32,
    estimates:      [MAX_STATES]f32,
    parents:        [MAX_STATES]int,
    closed:         [MAX_STATES]bool,
    heap:           [MAX_STATES]int,
    heap_positions: [MAX_STATES]int,
    heap_count:     int,
}

grid_valid :: proc(grid: Grid) -> bool {
    return grid.width > 1 && grid.height > 1 && grid.width <= MAX_GRID_WIDTH &&
        grid.height <= MAX_GRID_HEIGHT && len(grid.heights) >= grid.width * grid.height
}

// Returns the fraction of a road step that runs along a nearby shoreline.
// The wet/dry mask gradient is normal to the bank, so a square crossing has
// no surcharge while an increasingly oblique crossing pays more. Away from a
// shoreline there is no meaningful crossing direction and therefore no
// surcharge.
water_mask_at :: #force_inline proc(grid: Grid, x, z: int) -> f32 {
    sample_x := clamp(x, 0, grid.width - 1)
    sample_z := clamp(z, 0, grid.height - 1)
    return grid.heights[sample_z * grid.width + sample_x] <= grid.sea_level ? f32(1) : f32(0)
}

water_crossing_obliqueness :: proc(grid: Grid, x, z, step_x, step_z: int) -> f32 {
    normal_x := water_mask_at(grid, x + 1, z) - water_mask_at(grid, x - 1, z)
    normal_z := water_mask_at(grid, x, z + 1) - water_mask_at(grid, x, z - 1)
    normal_length := f32(math.sqrt(f64(normal_x * normal_x + normal_z * normal_z)))
    step_length := f32(math.sqrt(f64(step_x * step_x + step_z * step_z)))
    if normal_length <= .001 || step_length <= .001 do return 0
    cross := f32(step_x) * normal_z - f32(step_z) * normal_x
    tangential := math.abs(cross) / (step_length * normal_length)
    return tangential * tangential
}

// Plan on a regularly sampled height grid. Grid spacing belongs to Config so
// the same policy can be exercised in a lab and by terrain generation.
workspace_heap_swap :: proc(work: ^Workspace, a, b: int) {
    work.heap[a], work.heap[b] = work.heap[b], work.heap[a]
    work.heap_positions[work.heap[a]] = a
    work.heap_positions[work.heap[b]] = b
}

workspace_heap_raise :: proc(work: ^Workspace, position: int) {
    cursor := position
    for cursor > 0 {
        parent := (cursor - 1) / 2
        if work.estimates[work.heap[parent]] <= work.estimates[work.heap[cursor]] do break
        workspace_heap_swap(work, parent, cursor)
        cursor = parent
    }
}

workspace_heap_push_or_raise :: proc(work: ^Workspace, state: int) {
    position := work.heap_positions[state]
    if position >= 0 {
        workspace_heap_raise(work, position)
        return
    }
    position = work.heap_count
    work.heap[position] = state
    work.heap_positions[state] = position
    work.heap_count += 1
    workspace_heap_raise(work, position)
}

workspace_heap_pop :: proc(work: ^Workspace) -> int {
    if work.heap_count <= 0 do return -1
    result := work.heap[0]
    work.heap_count -= 1
    work.heap_positions[result] = -1
    if work.heap_count == 0 do return result
    work.heap[0] = work.heap[work.heap_count]
    work.heap_positions[work.heap[0]] = 0
    cursor := 0
    for {
        left, right, best := cursor * 2 + 1, cursor * 2 + 2, cursor
        if left < work.heap_count && work.estimates[work.heap[left]] < work.estimates[work.heap[best]] do best = left
        if right < work.heap_count && work.estimates[work.heap[right]] < work.estimates[work.heap[best]] do best = right
        if best == cursor do break
        workspace_heap_swap(work, cursor, best)
        cursor = best
    }
    return result
}

plan :: proc(work: ^Workspace, grid: Grid, config: Config, start, finish: Point) -> Result {
    result: Result
    if work == nil || !grid_valid(grid) || config.cell_size <= 0 do return result
    cell_count := grid.width * grid.height
    state_count := cell_count * MAX_DIRECTIONS
    work.heap_count = 0
    for index in 0 ..< state_count {
        work.scores[index] = f32(1e30)
        work.estimates[index] = f32(1e30)
        work.parents[index] = -1
        work.closed[index] = false
        work.heap_positions[index] = -1
    }
    sx := clamp(int(math.round((start.x - grid.origin_x) / config.cell_size)), 0, grid.width - 1)
    sz := clamp(int(math.round((start.z - grid.origin_z) / config.cell_size)), 0, grid.height - 1)
    fx := clamp(int(math.round((finish.x - grid.origin_x) / config.cell_size)), 0, grid.width - 1)
    fz := clamp(int(math.round((finish.z - grid.origin_z) / config.cell_size)), 0, grid.height - 1)
    start_cell, finish_cell := sz * grid.width + sx, fz * grid.width + fx
    initial_estimate := math.sqrt(f32((fx - sx) * (fx - sx) + (fz - sz) * (fz - sz))) *
        config.cell_size * config.length_cost * config.heuristic_weight
    for direction in 0 ..< MAX_DIRECTIONS {
        state := start_cell * MAX_DIRECTIONS + direction
        work.scores[state] = 0
        work.estimates[state] = initial_estimate
        workspace_heap_push_or_raise(work, state)
    }
    // Ordered around the compass so direction deltas have geometric meaning.
    // The 2:1 moves give steep terrain enough lateral run to form switchbacks
    // that an eight-neighbor lattice cannot represent.
    offsets := [MAX_DIRECTIONS][2]int {
        {-1,0}, {-2,-1}, {-1,-1}, {-1,-2}, {0,-1}, {1,-2}, {1,-1}, {2,-1},
        {1,0}, {2,1}, {1,1}, {1,2}, {0,1}, {-1,2}, {-1,1}, {-2,1},
    }
    finish_state := -1
    for {
        current := workspace_heap_pop(work)
        if current < 0 do return result
        if work.closed[current] do continue
        current_cell := current / MAX_DIRECTIONS
        if current_cell == finish_cell {
            finish_state = current
            break
        }
        work.closed[current] = true
        result.expanded += 1
        cx, cz := current_cell % grid.width, current_cell / grid.width
        current_height := grid.heights[current_cell]
        incoming_direction := current % MAX_DIRECTIONS
        for offset, direction in offsets {
            nx, nz := cx + offset[0], cz + offset[1]
            if nx < 0 || nz < 0 || nx >= grid.width || nz >= grid.height do continue
            next_cell := nz * grid.width + nx
            if len(grid.blocked) >= cell_count && grid.blocked[next_cell] do continue
            next := next_cell * MAX_DIRECTIONS + direction
            if work.closed[next] do continue
            step_length := math.sqrt(f32(offset[0] * offset[0] + offset[1] * offset[1]))
            distance := config.cell_size * step_length
            rise := grid.heights[next_cell] - current_height
            grade := math.abs(rise) / distance
            if grade > config.maximum_grade do continue
            step_cost := distance * config.length_cost + grade * distance * config.grade_cost
            sample_count := max(abs(offset[0]), abs(offset[1]))
            for sample in 1 ..= sample_count {
                amount := f32(sample) / f32(sample_count)
                sample_x := clamp(int(math.round(f32(cx) + f32(offset[0]) * amount)), 0, grid.width - 1)
                sample_z := clamp(int(math.round(f32(cz) + f32(offset[1]) * amount)), 0, grid.height - 1)
                sample_cell := sample_z * grid.width + sample_x
                if len(grid.blocked) >= cell_count && grid.blocked[sample_cell] {
                    step_cost = f32(1e30)
                    break
                }
                sample_height := grid.heights[sample_cell]
                if sample_height <= grid.sea_level {
                    water_step_cost := config.water_cost * distance / f32(sample_count)
                    // Crossing along the bank costs up to twice as much as
                    // crossing its local normal. This keeps water expensive
                    // while rewarding short, square bridge approaches.
                    step_cost += water_step_cost *
                        (1 + water_crossing_obliqueness(grid, sample_x, sample_z, offset[0], offset[1]))
                }
                if sample < sample_count {
                    expected_height := current_height + rise * amount
                    deviation_grade := math.abs(sample_height - expected_height) / config.cell_size
                    step_cost += deviation_grade * deviation_grade * config.steep_grade_cost * config.cell_size
                }
            }
            if step_cost >= f32(1e30) do continue
            if current_cell != start_cell && incoming_direction != direction {
                direction_delta := abs(incoming_direction - direction)
                direction_delta = min(direction_delta, MAX_DIRECTIONS - direction_delta)
                turn_amount := f32(direction_delta) / f32(MAX_DIRECTIONS / 2)
                step_cost += config.turn_cost * turn_amount
                if direction_delta >= 6 do step_cost += config.switchback_cost * (turn_amount - .625)
            }
            candidate := work.scores[current] + step_cost
            if candidate >= work.scores[next] do continue
            dx, dz := fx - nx, fz - nz
            heuristic := math.sqrt(f32(dx * dx + dz * dz)) * config.cell_size * config.length_cost * config.heuristic_weight
            work.scores[next] = candidate
            work.estimates[next] = candidate + heuristic
            work.parents[next] = current
            workspace_heap_push_or_raise(work, next)
        }
    }
    reverse: [MAX_PATH_POINTS]int
    reverse_count := 0
    cursor := finish_state
    for cursor >= 0 && reverse_count < len(reverse) {
        reverse[reverse_count] = cursor
        reverse_count += 1
        if cursor / MAX_DIRECTIONS == start_cell do break
        cursor = work.parents[cursor]
    }
    if reverse_count == 0 || reverse[reverse_count - 1] / MAX_DIRECTIONS != start_cell do return result
    result.point_count = reverse_count
    for output_index in 0 ..< reverse_count {
        cell := reverse[reverse_count - 1 - output_index] / MAX_DIRECTIONS
        x, z := cell % grid.width, cell / grid.width
        result.points[output_index] = {grid.origin_x + f32(x) * config.cell_size, grid.origin_z + f32(z) * config.cell_size}
    }
    result.total_cost = work.scores[finish_state]
    result.found = true
    return result
}
