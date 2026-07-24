package markov
import "base:runtime"

import "core:container/priority_queue"
import "core:log"
import "core:math/rand"
import "core:mem"
import "core:slice"

// Board for A* search
Board :: struct {
    state:             []u8,
    parent_index:      int,
    depth:             int,
    backward_estimate: int,
    forward_estimate:  int,
}

board_rank :: proc(b: ^Board, rng: runtime.Random_Generator, depth_coeff: f64) -> f64 {
    result: f64
    if depth_coeff < 0.0 {
        result = 1000 - f64(b.depth)
    } else {
        result = f64(b.forward_estimate + b.backward_estimate) + 2.0 * depth_coeff * f64(b.depth)
    }
    return result + 0.0001 * rand.float64(rng)
}

board_trajectory :: proc(index: int, database: []Board, allocator := context.allocator) -> [][]u8 {
    result := make([dynamic][]u8, allocator)
    idx := index
    for database[idx].parent_index >= 0 {
        append(&result, database[idx].state)
        idx = database[idx].parent_index
    }
    slice.reverse(result[:])
    return result[:]
}

// State hash for visited map
state_hash :: proc(state: []u8) -> u64 {
    result: u64 = 17
    for b in state {
        result = result * 29 + u64(b)
    }
    return result
}

state_equals :: proc(a, b: []u8) -> bool {
    if len(a) != len(b) { return false }
    for i in 0 ..< len(a) {
        if a[i] != b[i] { return false }
    }
    return true
}

// Priority queue item for A* frontier
Frontier_Item :: struct {
    index: int,
    rank:  f64,
}

frontier_less :: proc(a, b: Frontier_Item) -> bool {
    return a.rank < b.rank
}

// A* Search
search_run :: proc(
    present: []u8,
    future: []int,
    rules: []Rule,
    m: [3]int,
    c: int,
    all: bool,
    limit: int,
    depth_coeff: f64,
    seed: u64,
    allocator := context.allocator,
) -> [][]u8 {
    size := len(present)

    bpotentials := make([][]int, c, allocator)
    fpotentials := make([][]int, c, allocator)
    for i in 0 ..< c {
        bpotentials[i] = make([]int, size, allocator)
        fpotentials[i] = make([]int, size, allocator)
    }

    compute_backward_potentials(bpotentials, future, m, rules)
    root_backward := backward_pointwise(bpotentials, present)
    compute_forward_potentials(fpotentials, present, m, rules)
    root_forward := forward_pointwise(fpotentials, future)

    if root_backward < 0 || root_forward < 0 {
        log.error("INCORRECT PROBLEM")
        return nil
    }
    log.infof("root estimate = (%d, %d)", root_backward, root_forward)

    if root_backward == 0 {
        return make([][]u8, 0, allocator)
    }

    root_state := make([]u8, size, allocator)
    copy(root_state, present)

    root_board: Board = {root_state, -1, 0, root_backward, root_forward}

    database := make([dynamic]Board, allocator)
    append(&database, root_board)

    visited := make(map[u64]int, 1024, allocator)
    visited[state_hash(present)] = 0

    rng_state := rand.create(seed)
    rng := rand.default_random_generator(&rng_state)

    frontier: priority_queue.Priority_Queue(Frontier_Item)
    priority_queue.init(&frontier, frontier_less, priority_queue.default_swap_proc(Frontier_Item), 1024, allocator)
    priority_queue.push(&frontier, Frontier_Item{0, board_rank(&root_board, rng, depth_coeff)})

    record := root_backward + root_forward

    for priority_queue.len(frontier) > 0 && (limit < 0 || len(database) < limit) {
        parent_item := priority_queue.pop(&frontier)
        parent_index := parent_item.index
        parent_board := &database[parent_index]

        children :=
            all ? all_child_states(parent_board.state, m, rules) : one_child_states(parent_board.state, m, rules)

        for child_state in children {
            child_hash := state_hash(child_state)

            if child_hash in visited {
                child_index := visited[child_hash]
                old_board := &database[child_index]
                if parent_board.depth + 1 < old_board.depth {
                    old_board.depth = parent_board.depth + 1
                    old_board.parent_index = parent_index
                    if old_board.backward_estimate >= 0 && old_board.forward_estimate >= 0 {
                        priority_queue.push(
                            &frontier,
                            Frontier_Item{child_index, board_rank(old_board, rng, depth_coeff)},
                        )
                    }
                }
            } else {
                child_backward := backward_pointwise(bpotentials, child_state)
                compute_forward_potentials(fpotentials, child_state, m, rules)
                child_forward := forward_pointwise(fpotentials, future)

                if child_backward < 0 || child_forward < 0 {
                    continue
                }

                child_board: Board = {child_state, parent_index, parent_board.depth + 1, child_backward, child_forward}
                append(&database, child_board)
                child_index := len(database) - 1
                visited[child_hash] = child_index

                if child_forward == 0 {
                    log.infof("found trajectory of length %d, visited %d states", parent_board.depth + 1, len(visited))
                    return board_trajectory(child_index, database[:], allocator)
                } else {
                    if limit < 0 && child_backward + child_forward <= record {
                        record = child_backward + child_forward
                        log.infof("found state of record estimate %d = %d + %d", record, child_backward, child_forward)
                    }
                    priority_queue.push(
                        &frontier,
                        Frontier_Item{child_index, board_rank(&child_board, rng, depth_coeff)},
                    )
                }
            }
        }
    }

    return nil
}

// Generate one child state per matching rule position
one_child_states :: proc(state: []u8, m: [3]int, rules: []Rule, allocator := context.temp_allocator) -> [][]u8 {
    result := make([dynamic][]u8, allocator)

    for &rule in rules {
        for y in 0 ..< m.y {
            for x in 0 ..< m.x {
                if search_matches(&rule, x, y, state, m) {
                    append(&result, search_applied(&rule, x, y, state, m, allocator))
                }
            }
        }
    }
    return result[:]
}

search_matches :: proc(rule: ^Rule, x, y: int, state: []u8, m: [3]int) -> bool {
    if x + rule.im.x > m.x || y + rule.im.y > m.y {
        return false
    }

    dy, dx := 0, 0
    for di in 0 ..< len(rule.input) {
        if (rule.input[di] & (1 << uint(state[x + dx + (y + dy) * m.x]))) == 0 {
            return false
        }
        dx += 1
        if dx == rule.im.x {
            dx = 0
            dy += 1
        }
    }
    return true
}

search_applied :: proc(rule: ^Rule, x, y: int, state: []u8, m: [3]int, allocator := context.temp_allocator) -> []u8 {
    result := make([]u8, len(state), allocator)
    copy(result, state)

    for dz in 0 ..< rule.om.z {
        for dy in 0 ..< rule.om.y {
            for dx in 0 ..< rule.om.x {
                new_value := rule.output[dx + dy * rule.om.x + dz * rule.om.x * rule.om.y]
                if new_value != 0xff {
                    result[x + dx + (y + dy) * m.x] = new_value
                }
            }
        }
    }
    return result
}

// Generate all non-overlapping child states
all_child_states :: proc(state: []u8, m: [3]int, rules: []Rule, allocator := context.temp_allocator) -> [][]u8 {
    tiles := make([dynamic]Match_Tile, allocator)
    amounts := make([]int, len(state), allocator)

    for i in 0 ..< len(state) {
        x := i % m.x
        y := i / m.x
        for &rule in rules {
            if search_matches(&rule, x, y, state, m) {
                append(&tiles, Match_Tile{&rule, i})
                for dy in 0 ..< rule.im.y {
                    for dx in 0 ..< rule.im.x {
                        amounts[x + dx + (y + dy) * m.x] += 1
                    }
                }
            }
        }
    }

    mask := make([]bool, len(tiles), allocator)
    for i in 0 ..< len(mask) { mask[i] = true }

    solution := make([dynamic]Match_Tile, allocator)
    result := make([dynamic][]u8, allocator)

    enumerate_solutions(&result, &solution, tiles[:], amounts, mask, state, m, allocator)
    return result[:]
}

max_positive_index :: proc(amounts: []int) -> int {
    max_val := 0
    argmax := -1
    for i in 0 ..< len(amounts) {
        if amounts[i] > max_val {
            max_val = amounts[i]
            argmax = i
        }
    }
    return argmax
}

is_inside :: proc(px, py: int, rule: ^Rule, x, y: int) -> bool {
    return x <= px && px < x + rule.im.x && y <= py && py < y + rule.im.y
}

tiles_overlap :: proc(r0: ^Rule, i0: int, r1: ^Rule, i1: int, m: [3]int) -> bool {
    x0, y0 := i0 % m.x, i0 / m.x
    x1, y1 := i1 % m.x, i1 / m.x
    for dy in 0 ..< r0.im.y {
        for dx in 0 ..< r0.im.x {
            if is_inside(x0 + dx, y0 + dy, r1, x1, y1) {
                return true
            }
        }
    }
    return false
}

Match_Tile :: struct {
    rule: ^Rule,
    i:    int,
}

enumerate_solutions :: proc(
    children: ^[dynamic][]u8,
    solution: ^[dynamic]Match_Tile,
    tiles: []Match_Tile,
    amounts: []int,
    mask: []bool,
    state: []u8,
    m: [3]int,
    allocator: mem.Allocator,
) {
    I := max_positive_index(amounts)
    if I < 0 {
        append(children, apply_solution(state, solution[:], m, allocator))
        return
    }

    X, Y := I % m.x, I / m.x

    cover := make([dynamic]Match_Tile, context.temp_allocator)
    for l in 0 ..< len(tiles) {
        tile := tiles[l]
        if mask[l] && is_inside(X, Y, tile.rule, tile.i % m.x, tile.i / m.x) {
            append(&cover, tile)
        }
    }

    for tile in cover {
        append(solution, tile)

        intersecting := make([dynamic]int, context.temp_allocator)
        for l in 0 ..< len(tiles) {
            if mask[l] {
                t := tiles[l]
                if tiles_overlap(tile.rule, tile.i, t.rule, t.i, m) {
                    append(&intersecting, l)
                }
            }
        }

        for l in intersecting { hide_tile(l, false, tiles, amounts, mask, m) }
        enumerate_solutions(children, solution, tiles, amounts, mask, state, m, allocator)
        for l in intersecting { hide_tile(l, true, tiles, amounts, mask, m) }

        pop(solution)
    }
}

hide_tile :: proc(l: int, unhide: bool, tiles: []Match_Tile, amounts: []int, mask: []bool, m: [3]int) {
    mask[l] = unhide
    tile := tiles[l]
    x, y := tile.i % m.x, tile.i / m.x
    incr := unhide ? 1 : -1
    for dy in 0 ..< tile.rule.im.y {
        for dx in 0 ..< tile.rule.im.x {
            amounts[x + dx + (y + dy) * m.x] += incr
        }
    }
}

apply_solution :: proc(state: []u8, solution: []Match_Tile, m: [3]int, allocator: mem.Allocator) -> []u8 {
    result := make([]u8, len(state), allocator)
    copy(result, state)
    for tile in solution {
        x, y := tile.i % m.x, tile.i / m.x
        for dy in 0 ..< tile.rule.om.y {
            for dx in 0 ..< tile.rule.om.x {
                result[x + dx + (y + dy) * m.x] = tile.rule.output[dx + dy * tile.rule.om.x]
            }
        }
    }
    return result
}
