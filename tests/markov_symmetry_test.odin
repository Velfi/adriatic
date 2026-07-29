package tests

import "core:testing"

import back "../packages/back"
import markov "../packages/markov"

@(test)
markov_symmetry_releases_unselected_candidates :: proc(t: ^testing.T) {
    tracker: back.Tracking_Allocator
    back.tracking_allocator_init(&tracker, context.allocator)
    defer back.tracking_allocator_destroy(&tracker)
    allocator := back.tracking_allocator(&tracker)

    input := make([]int, 2, allocator)
    input[0] = 1
    input[1] = 2
    output := make([]u8, 2, allocator)
    output[0] = 0
    output[1] = 1
    base: markov.Rule
    markov.rule_init(&base, input, {2, 1, 1}, output, {2, 1, 1}, 2, 1, allocator)

    rules := markov.rule_square_symmetries(&base, 2, markov.SYMMETRY_2D_IDENTITY, allocator)
    testing.expect_value(t, len(rules), 1)

    for &rule in rules {
        markov.rule_destroy(&rule, allocator)
    }
    delete(rules)

    testing.expect_value(t, len(tracker.allocation_map), 0)
}
