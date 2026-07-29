// Package lsystem expands deterministic or stochastic context-free grammars
// and interprets their words as renderer-independent plant structure.
package lsystem

import "core:math"
import "core:math/linalg"

Vec3 :: [3]f32

Alternative :: struct {
    text:   string,
    weight: u32,
}

Rule :: struct {
    symbol:       u8,
    alternatives: []Alternative,
}

Grammar :: struct {
    axiom: string,
    rules: []Rule,
}

Expand_Config :: struct {
    iterations:  int,
    seed:        u64,
    max_symbols: int,
}

Expand_Error :: enum {
    None,
    Invalid_Iterations,
    Symbol_Limit,
    Empty_Production,
}

Expand_Result :: struct {
    word:  [dynamic]u8,
    error: Expand_Error,
}

destroy_word :: proc(result: ^Expand_Result) {
    if result == nil do return
    delete(result.word)
    result.word = nil
}

random_next :: proc(state: ^u64) -> u64 {
    // SplitMix64 makes stochastic grammars reproducible without global state.
    state^ += 0x9e3779b97f4a7c15
    z := state^
    z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ~ (z >> 27)) * 0x94d049bb133111eb
    return z ~ (z >> 31)
}

find_rule :: proc(grammar: Grammar, symbol: u8) -> ^Rule {
    for &rule in grammar.rules {
        if rule.symbol == symbol do return &rule
    }
    return nil
}

choose_alternative :: proc(rule: ^Rule, random: ^u64) -> (^Alternative, bool) {
    if rule == nil || len(rule.alternatives) == 0 do return nil, false
    total: u64
    for &alternative in rule.alternatives {
        total += u64(max(alternative.weight, 1))
    }
    if total == 0 do return nil, false
    choice := random_next(random) % total
    for &alternative in rule.alternatives {
        weight := u64(max(alternative.weight, 1))
        if choice < weight do return &alternative, true
        choice -= weight
    }
    return nil, false
}

expand :: proc(grammar: Grammar, config: Expand_Config) -> Expand_Result {
    result: Expand_Result
    if config.iterations < 0 {
        result.error = .Invalid_Iterations
        return result
    }
    limit := config.max_symbols
    if limit == 0 do limit = 1_000_000
    limit = max(limit, 0)
    if len(grammar.axiom) > limit {
        result.error = .Symbol_Limit
        return result
    }
    result.word = make([dynamic]u8, 0, len(grammar.axiom))
    append(&result.word, grammar.axiom)
    random := config.seed

    for _ in 0 ..< config.iterations {
        next := make([dynamic]u8, 0, min(limit, max(len(result.word) * 2, 16)))
        failed := false
        for symbol in result.word {
            rule := find_rule(grammar, symbol)
            if rule == nil {
                if len(next) >= limit {
                    failed = true
                    break
                }
                append(&next, symbol)
                continue
            }
            alternative, ok := choose_alternative(rule, &random)
            if !ok || len(alternative.text) == 0 {
                result.error = .Empty_Production
                failed = true
                break
            }
            if len(next) + len(alternative.text) > limit {
                result.error = .Symbol_Limit
                failed = true
                break
            }
            append(&next, alternative.text)
        }
        if failed {
            if result.error == .None do result.error = .Symbol_Limit
            delete(next)
            delete(result.word)
            result.word = nil
            return result
        }
        delete(result.word)
        result.word = next
    }
    return result
}

Segment :: struct {
    start:        Vec3,
    end:          Vec3,
    radius_start: f32,
    radius_end:   f32,
    depth:        int,
}

Leaf :: struct {
    position: Vec3,
    forward:  Vec3,
    up:       Vec3,
    depth:    int,
}

Plant :: struct {
    segments: [dynamic]Segment,
    leaves:   [dynamic]Leaf,
}

destroy_plant :: proc(plant: ^Plant) {
    if plant == nil do return
    delete(plant.segments)
    delete(plant.leaves)
    plant^ = {}
}

Turtle_Config :: struct {
    origin:       Vec3,
    forward:      Vec3,
    up:           Vec3,
    step:         f32,
    step_scale:   f32,
    angle:        f32,
    radius:       f32,
    radius_scale: f32,
}

Interpret_Error :: enum {
    None,
    Stack_Underflow,
    Unclosed_Branch,
    Invalid_Basis,
}

Interpret_Result :: struct {
    plant: Plant,
    error: Interpret_Error,
}

Turtle_State :: struct {
    position: Vec3,
    forward:  Vec3,
    up:       Vec3,
    step:     f32,
    radius:   f32,
    depth:    int,
}

rotate_vector :: proc(vector, axis: Vec3, angle: f32) -> Vec3 {
    unit_axis := linalg.normalize0(axis)
    cosine := f32(math.cos(angle))
    sine := f32(math.sin(angle))
    return(
        vector * cosine +
        linalg.cross(unit_axis, vector) * sine +
        unit_axis * linalg.dot(unit_axis, vector) * (1 - cosine) \
    )
}

orthonormalize :: proc(state: ^Turtle_State) -> bool {
    state.forward = linalg.normalize0(state.forward)
    right := linalg.normalize0(linalg.cross(state.forward, state.up))
    if linalg.dot(state.forward, state.forward) < .5 || linalg.dot(right, right) < .5 do return false
    state.up = linalg.normalize0(linalg.cross(right, state.forward))
    return true
}

rotate_turtle :: proc(state: ^Turtle_State, axis: Vec3, angle: f32) -> bool {
    state.forward = rotate_vector(state.forward, axis, angle)
    state.up = rotate_vector(state.up, axis, angle)
    return orthonormalize(state)
}

// Command alphabet:
// F draw, f move, +-/&^ yaw/pitch, \ and / roll, | turn around,
// [ push branch, ] pop branch, and L emit a foliage attachment.
interpret :: proc(word: []u8, config: Turtle_Config) -> Interpret_Result {
    result: Interpret_Result
    cfg := config
    if linalg.dot(cfg.forward, cfg.forward) == 0 do cfg.forward = {0, 1, 0}
    if linalg.dot(cfg.up, cfg.up) == 0 do cfg.up = {0, 0, 1}
    if cfg.step == 0 do cfg.step = 1
    if cfg.step_scale == 0 do cfg.step_scale = 1
    if cfg.angle == 0 do cfg.angle = math.PI / 6
    if cfg.radius == 0 do cfg.radius = .1
    if cfg.radius_scale == 0 do cfg.radius_scale = .72
    state := Turtle_State {
        position = cfg.origin,
        forward  = cfg.forward,
        up       = cfg.up,
        step     = cfg.step,
        radius   = cfg.radius,
    }
    if !orthonormalize(&state) {
        result.error = .Invalid_Basis
        return result
    }
    stack := make([dynamic]Turtle_State)
    defer delete(stack)

    for symbol in word {
        switch symbol {
        case 'F':
            next := state.position + state.forward * state.step
            append(
                &result.plant.segments,
                Segment {
                    start = state.position,
                    end = next,
                    radius_start = state.radius,
                    radius_end = state.radius * cfg.radius_scale,
                    depth = state.depth,
                },
            )
            state.position = next
            state.step *= cfg.step_scale
            state.radius *= cfg.radius_scale
        case 'f':
            state.position += state.forward * state.step
            state.step *= cfg.step_scale
        case '+':
            rotate_turtle(&state, state.up, cfg.angle)
        case '-':
            rotate_turtle(&state, state.up, -cfg.angle)
        case '&':
            right := linalg.cross(state.forward, state.up)
            rotate_turtle(&state, right, cfg.angle)
        case '^':
            right := linalg.cross(state.forward, state.up)
            rotate_turtle(&state, right, -cfg.angle)
        case '\\':
            rotate_turtle(&state, state.forward, cfg.angle)
        case '/':
            rotate_turtle(&state, state.forward, -cfg.angle)
        case '|':
            rotate_turtle(&state, state.up, math.PI)
        case '[':
            append(&stack, state)
            state.depth += 1
            state.radius *= cfg.radius_scale
        case ']':
            if len(stack) == 0 {
                result.error = .Stack_Underflow
                destroy_plant(&result.plant)
                return result
            }
            state = pop(&stack)
        case 'L':
            append(
                &result.plant.leaves,
                Leaf{position = state.position, forward = state.forward, up = state.up, depth = state.depth},
            )
        }
    }
    if len(stack) != 0 {
        result.error = .Unclosed_Branch
        destroy_plant(&result.plant)
    }
    return result
}
