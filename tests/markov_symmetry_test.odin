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

@(test)
markov_interpreter_destroy_releases_loaded_model :: proc(t: ^testing.T) {
    tracker: back.Tracking_Allocator
    back.tracking_allocator_init(&tracker, context.allocator)
    defer back.tracking_allocator_destroy(&tracker)
    allocator := back.tracking_allocator(&tracker)

    model := markov.node(
        markov.Proc_Tag.one,
        []markov.Proc_Attr {
            markov.kattr(.values, markov.values_count(2)),
            markov.kattr(
                .in_,
                markov.match_layer(
                    markov.match_row(markov.one_of(markov.sym(0)), allocator = allocator),
                    allocator = allocator,
                ),
                allocator = allocator,
            ),
            markov.kattr(
                .out,
                markov.write_layer(markov.write_row(markov.sym(1), allocator = allocator), allocator = allocator),
                allocator = allocator,
            ),
        },
        allocator = allocator,
    )
    ip, loaded := markov.load_model_proc(model, {2, 2, 1}, allocator)
    testing.expect(t, loaded)
    if loaded {
        markov.interpreter_destroy(ip)
    }

    testing.expect_value(t, len(tracker.allocation_map), 0)
}

@(test)
markov_frames_destroy_releases_run_output :: proc(t: ^testing.T) {
    tracker: back.Tracking_Allocator
    back.tracking_allocator_init(&tracker, context.allocator)
    defer back.tracking_allocator_destroy(&tracker)
    allocator := back.tracking_allocator(&tracker)

    model := markov.node(
        markov.Proc_Tag.one,
        []markov.Proc_Attr {
            markov.kattr(.values, markov.values_count(2)),
            markov.kattr(
                .in_,
                markov.match_layer(
                    markov.match_row(markov.one_of(markov.sym(0)), allocator = allocator),
                    allocator = allocator,
                ),
                allocator = allocator,
            ),
            markov.kattr(
                .out,
                markov.write_layer(markov.write_row(markov.sym(1), allocator = allocator), allocator = allocator),
                allocator = allocator,
            ),
        },
        allocator = allocator,
    )
    ip, loaded := markov.load_model_proc(model, {2, 2, 1}, allocator)
    testing.expect(t, loaded)
    if loaded {
        frames := markov.run(ip, 1, 4, false, allocator)
        markov.frames_destroy(&frames, allocator)
        markov.interpreter_destroy(ip)
    }

    testing.expect_value(t, len(tracker.allocation_map), 0)
}

@(test)
markov_convenience_nodes_release_temporary_containers :: proc(t: ^testing.T) {
    tracker: back.Tracking_Allocator
    back.tracking_allocator_init(&tracker, context.allocator)
    defer back.tracking_allocator_destroy(&tracker)
    allocator := back.tracking_allocator(&tracker)

    child := markov.one(markov.kattr(.steps, 1), allocator = allocator)
    model := markov.sequence(markov.kattr(.values, markov.values_count(2)), child, allocator = allocator)
    markov.proc_node_destroy(&model, allocator)

    testing.expect_value(t, len(tracker.allocation_map), 0)
}
