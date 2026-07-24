package markov
import "base:intrinsics"
import "base:runtime"

import "core:math/rand"
import "core:mem"
import "core:strings"

SAFE_INTERNAL_SYMBOLS :: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()+,-.:;<=>?@[]^_`{}~"

// Grid represents the state of the world
Grid :: struct {
    state:       []u8,
    mask:        []bool,
    state_buf:   []u8,
    m:           [3]int, // dimensions
    c:           u8, // color count
    chars:       [256]u8, // index -> char
    values:      [256]u8, // char -> index (0xff if not present)
    waves:       [256]int, // char -> bitmask
    folder:      string,
    transparent: int,
}

is_reserved_internal_symbol :: proc(ch: u8) -> bool {
    return ch == 0 || ch == '*' || ch == '/' || ch == '|' || ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

// value_string_for_count generates internal symbol bytes for procedural domains.
value_string_for_count :: proc(count: int, allocator := context.allocator) -> (string, bool) {
    if count <= 0 || count > 255 {
        return "", false
    }

    used: [256]bool
    for i in 0 ..< len(used) {
        used[i] = false
    }
    for c in SAFE_INTERNAL_SYMBOLS {
        used[u8(c)] = true
    }
    for i in 0 ..< 256 {
        ch := u8(i)
        if is_reserved_internal_symbol(ch) {
            used[ch] = true
        }
    }

    result := make([dynamic]u8, 0, count, allocator)

    // Prefer a readable stable alphabet first.
    for c in SAFE_INTERNAL_SYMBOLS {
        ch := u8(c)
        if is_reserved_internal_symbol(ch) {
            continue
        }
        append(&result, ch)
        if len(result) == count {
            return string(result[:]), true
        }
    }

    // Then fall back to any remaining non-reserved bytes.
    for i in 1 ..< 256 {
        ch := u8(i)
        if used[ch] || is_reserved_internal_symbol(ch) {
            continue
        }
        append(&result, ch)
        if len(result) == count {
            return string(result[:]), true
        }
    }

    return "", false
}

grid_init :: proc(g: ^Grid, m: [3]int, value_string: string, allocator := context.allocator) -> bool {
    g.m = m

    // Remove spaces from value_string (C# does this)
    values_no_space, _ := strings.remove_all(value_string, " ", context.temp_allocator)

    g.c = u8(len(values_no_space))

    // Initialize lookup tables
    for i in 0 ..< 256 {
        g.values[i] = 0xff
    }

    for i in 0 ..< int(g.c) {
        ch := values_no_space[i]
        if g.values[ch] != 0xff {
            return false // duplicate value
        }
        g.chars[i] = ch
        g.values[ch] = u8(i)
        g.waves[ch] = 1 << uint(i)
    }

    // Wildcard matches all
    g.waves['*'] = (1 << uint(g.c)) - 1

    size := m.x * m.y * m.z
    g.state = make([]u8, size, allocator)
    g.state_buf = make([]u8, size, allocator)
    g.mask = make([]bool, size, allocator)

    return true
}

grid_init_count :: proc(g: ^Grid, m: [3]int, count: int, allocator := context.allocator) -> bool {
    values, ok := value_string_for_count(count, context.temp_allocator)
    if !ok {
        return false
    }
    return grid_init(g, m, values, allocator)
}

grid_destroy :: proc(g: ^Grid, allocator := context.allocator) {
    delete(g.state, allocator)
    delete(g.state_buf, allocator)
    delete(g.mask, allocator)
}

grid_clear :: proc(g: ^Grid) {
    mem.zero_slice(g.state)
}

grid_wave :: proc(g: ^Grid, values: string) -> int {
    sum := 0
    for ch in values {
        sum |= 1 << uint(g.values[u8(ch)])
    }
    return sum
}

grid_wave_symbols :: proc(g: ^Grid, values: Symbol_Set) -> int {
    sum := 0
    chars := cast([]u8)values
    for ch in chars {
        sum |= 1 << uint(g.values[ch])
    }
    return sum
}

grid_idx :: #force_inline proc(g: ^Grid, p: [3]int) -> int {
    return p.x + p.y * g.m.x + p.z * g.m.x * g.m.y
}

grid_matches :: proc(g: ^Grid, rule: ^Rule, pos: [3]int) -> bool {
    d: [3]int
    for di in 0 ..< len(rule.input) {
        idx := pos.x + d.x + (pos.y + d.y) * g.m.x + (pos.z + d.z) * g.m.x * g.m.y
        if rule.input[di] & (1 << uint(g.state[idx])) == 0 {
            return false
        }
        d.x += 1
        if d.x == rule.im.x {
            d.x = 0
            d.y += 1
            if d.y == rule.im.y {
                d.y = 0
                d.z += 1
            }
        }
    }
    return true
}

// Rule represents a rewrite pattern
Rule :: struct {
    input:    []int, // bitmask patterns
    output:   []u8, // output values (0xff = unchanged)
    binput:   []u8, // optimized single-value version
    im:       [3]int, // input dimensions
    om:       [3]int, // output dimensions
    p:        f64, // probability
    ishifts:  [][][3]int, // [color][shifts] - each color has a slice of [3]int positions
    oshifts:  [][][3]int,
    original: bool,
}

rule_init :: proc(
    r: ^Rule,
    input: []int,
    im: [3]int,
    output: []u8,
    om: [3]int,
    c: int,
    p: f64,
    allocator := context.allocator,
) {
    r.input = input
    r.output = output
    r.im = im
    r.om = om
    r.p = p

    // Build ishifts - for each color, store positions where it appears in input
    r.ishifts = make([][][3]int, c, allocator)
    for cv in 0 ..< c {
        shifts := make([dynamic][3]int, allocator)
        for z in 0 ..< im.z {
            for y in 0 ..< im.y {
                for x in 0 ..< im.x {
                    w := input[x + y * im.x + z * im.x * im.y]
                    if w & (1 << uint(cv)) != 0 {
                        append(&shifts, [3]int{x, y, z})
                    }
                }
            }
        }
        r.ishifts[cv] = shifts[:]
    }

    // Build oshifts if dimensions match
    if om == im {
        r.oshifts = make([][][3]int, c, allocator)
        for cv in 0 ..< c {
            shifts := make([dynamic][3]int, allocator)
            for z in 0 ..< om.z {
                for y in 0 ..< om.y {
                    for x in 0 ..< om.x {
                        o := output[x + y * om.x + z * om.x * om.y]
                        if o == 0xff || int(o) == cv {
                            append(&shifts, [3]int{x, y, z})
                        }
                    }
                }
            }
            r.oshifts[cv] = shifts[:]
        }
    }

    // Build binput
    wildcard := (1 << uint(c)) - 1
    r.binput = make([]u8, len(input), allocator)
    for i in 0 ..< len(input) {
        w := input[i]
        if w == wildcard {
            r.binput[i] = 0xff
        } else {
            r.binput[i] = u8(intrinsics.count_trailing_zeros(u32(w)))
        }
    }
}

rule_same :: proc(a, b: ^Rule) -> bool {
    if a.im != b.im || a.om != b.om {
        return false
    }
    for i in 0 ..< len(a.input) {
        if a.input[i] != b.input[i] {
            return false
        }
    }
    for i in 0 ..< len(a.output) {
        if a.output[i] != b.output[i] {
            return false
        }
    }
    return true
}

// Match represents a rule match at a position
Match :: struct {
    r:   int,
    pos: [3]int,
}

// Node types
Node_Kind :: enum u8 {
    One,
    All,
    Parallel,
    Sequence,
    Markov,
    Path,
    Map,
    Convolution,
    ConvChain,
    Overlap_WFC,
    Tile_WFC,
}

// Forward declarations for node data
One_Node :: struct {
    using rule_base: Rule_Node,
}

All_Node :: struct {
    using rule_base: Rule_Node,
}

Parallel_Node :: struct {
    using rule_base: Rule_Node,
    newstate:        []u8,
}

Sequence_Node :: struct {
    using branch_base: Branch,
}

Markov_Node :: struct {
    using branch_base: Branch,
}

Path_Node :: struct {
    start:     int,
    finish:    int,
    substrate: int,
    value:     u8,
    inertia:   bool,
    longest:   bool,
    edges:     bool,
    vertices:  bool,
}

Map_Node :: struct {
    using branch_base: Branch,
    newgrid:           ^Grid,
    rules:             []Rule,
    nm:                [3]int,
    dm:                [3]int,
}

Convolution_Rule :: struct {
    input:     u8,
    output:    u8,
    values:    int, // bitmask
    sum_start: int,
    sum_end:   int,
}

Convolution_Node :: struct {
    rules:    []Convolution_Rule,
    kernel:   []int,
    periodic: bool,
    counter:  int,
    steps:    int,
    sumfield: [][]int,
}

ConvChain_Node :: struct {
    n:               int,
    temperature:     f64,
    weights:         []f64,
    c0, c1:          u8,
    substrate:       []bool,
    substrate_color: u8,
    counter:         int,
    steps:           int,
    sample:          []bool,
    sm:              [2]int,
}

// Branch is a node that contains children
Branch :: struct {
    parent:      ^Node,
    children:    [dynamic]^Node,
    child_index: int,
}

// RuleNode is a node that applies rules
Rule_Node :: struct {
    rules:             []Rule,
    counter:           int,
    steps:             int,
    matches:           [dynamic]Match,
    match_count:       int,
    last_matched_turn: int,
    match_mask:        [][]bool,
    potentials:        [][]int,
    fields:            []^Field,
    observations:      []^Observation,
    temperature:       f64,
    search:            bool,
    future_computed:   bool,
    future:            []int,
    trajectory:        [][]u8,
    limit:             int,
    depth_coeff:       f64,
    last:              []bool,
}

// Field for BFS computation
Field :: struct {
    recompute: bool,
    essential: bool,
    on:        int,
    from:      int,
    substrate: int,
    inversed:  bool,
    zero:      int,
}

// Observation for constraint propagation
Observation :: struct {
    from: u8,
    to:   int, // bitmask
}

// Wave for WFC
Wave :: struct {
    data:                       [][]bool,
    compatible:                 [][][]int,
    sums_of_ones:               []int,
    sums_of_weights:            []f64,
    sums_of_weight_log_weights: []f64,
    entropies:                  []f64,
}

// WFC base data
WFC_Base :: struct {
    using branch_base:         Branch,
    wave:                      ^Wave,
    propagator:                [][][]int,
    p_count:                   int,
    n:                         int,
    stack:                     [][2]int,
    stack_size:                int,
    weights:                   []f64,
    weight_log_weights:        []f64,
    sum_of_weights:            f64,
    sum_of_weight_log_weights: f64,
    starting_entropy:          f64,
    newgrid:                   ^Grid,
    startwave:                 ^Wave,
    map_:                      map[u8][]bool,
    periodic:                  bool,
    shannon:                   bool,
    distribution:              []f64,
    tries:                     int,
    name:                      string,
    first_go:                  bool,
    local_rng_state:           rand.Xoshiro256_Random_State,
    local_rng:                 runtime.Random_Generator,
}

Overlap_Node :: struct {
    using wfc_base: WFC_Base,
    patterns:       [][]u8,
}

Tile_Node :: struct {
    using wfc_base: WFC_Base,
    tiledata:       [dynamic][]u8,
    s:              int,
    sz:             int,
    overlap:        int,
    overlapz:       int,
}

// The main Node struct
Node :: struct {
    kind: Node_Kind,
    ip:   ^Interpreter,
    grid: ^Grid,
    data: struct #raw_union {
        one:         One_Node,
        all:         All_Node,
        parallel:    Parallel_Node,
        sequence:    Sequence_Node,
        markov:      Markov_Node,
        path:        Path_Node,
        map_:        Map_Node,
        convolution: Convolution_Node,
        convchain:   ConvChain_Node,
        overlap:     Overlap_Node,
        tile:        Tile_Node,
    },
}

// Interpreter orchestrates execution
Interpreter :: struct {
    root:      ^Node,
    current:   ^Node,
    grid:      ^Grid,
    startgrid: ^Grid,
    origin:    bool,
    rng_state: rand.Xoshiro256_Random_State,
    rng:       runtime.Random_Generator,
    changes:   [dynamic][3]int,
    first:     [dynamic]int,
    counter:   int,
    gif:       bool,
}

interpreter_init :: proc(ip: ^Interpreter, grid: ^Grid, origin: bool) {
    ip.grid = grid
    ip.startgrid = grid
    ip.origin = origin
    ip.changes = make([dynamic][3]int)
    ip.first = make([dynamic]int)
}

interpreter_destroy :: proc(ip: ^Interpreter) {
    delete(ip.changes)
    delete(ip.first)
}

// Frame represents a snapshot of the grid state
Frame :: struct {
    state: []u8,
    chars: []u8,
    m:     [3]int,
}
