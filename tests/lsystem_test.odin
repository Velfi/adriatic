package tests

import lsystem "../packages/lsystem"
import "core:testing"

@(test)
lsystem_expands_context_free_grammar :: proc(t: ^testing.T) {
    alternatives := [1]lsystem.Alternative{{text = "F[+F]F[-F]L"}}
    rules := [1]lsystem.Rule{{symbol = 'F', alternatives = alternatives[:]}}
    result := lsystem.expand({axiom = "F", rules = rules[:]}, {iterations = 2, seed = 9, max_symbols = 1_000})
    defer lsystem.destroy_word(&result)
    testing.expect_value(t, result.error, lsystem.Expand_Error.None)
    testing.expect_value(t, len(result.word), 51)
    testing.expect_value(t, result.word[0], u8('F'))
}

@(test)
lsystem_stochastic_expansion_is_seeded :: proc(t: ^testing.T) {
    alternatives := [2]lsystem.Alternative{{text = "F+F", weight = 1}, {text = "F-F", weight = 1}}
    rules := [1]lsystem.Rule{{symbol = 'F', alternatives = alternatives[:]}}
    grammar := lsystem.Grammar {
        axiom = "FFFFFFFF",
        rules = rules[:],
    }
    a := lsystem.expand(grammar, {iterations = 3, seed = 42})
    b := lsystem.expand(grammar, {iterations = 3, seed = 42})
    defer lsystem.destroy_word(&a)
    defer lsystem.destroy_word(&b)
    testing.expect_value(t, a.error, lsystem.Expand_Error.None)
    testing.expect_value(t, b.error, lsystem.Expand_Error.None)
    testing.expect_value(t, len(a.word), len(b.word))
    for symbol, index in a.word do testing.expect_value(t, symbol, b.word[index])
}

@(test)
lsystem_interpreter_restores_branch_state_and_emits_leaves :: proc(t: ^testing.T) {
    word := "F[+FL][-FL]FL"
    result := lsystem.interpret(transmute([]u8)word, {step = 2, radius = .5, radius_scale = .5})
    defer lsystem.destroy_plant(&result.plant)
    testing.expect_value(t, result.error, lsystem.Interpret_Error.None)
    testing.expect_value(t, len(result.plant.segments), 4)
    testing.expect_value(t, len(result.plant.leaves), 3)
    testing.expect_value(t, result.plant.segments[0].start, lsystem.Vec3{0, 0, 0})
    testing.expect_value(t, result.plant.segments[0].end, lsystem.Vec3{0, 2, 0})
    testing.expect_value(t, result.plant.segments[3].start, lsystem.Vec3{0, 2, 0})
    testing.expect_value(t, result.plant.segments[3].depth, 0)
}

@(test)
lsystem_rejects_malformed_and_unbounded_words :: proc(t: ^testing.T) {
    word := "F]"
    malformed := lsystem.interpret(transmute([]u8)word, {})
    defer lsystem.destroy_plant(&malformed.plant)
    testing.expect_value(t, malformed.error, lsystem.Interpret_Error.Stack_Underflow)

    alternatives := [1]lsystem.Alternative{{text = "FF"}}
    rules := [1]lsystem.Rule{{symbol = 'F', alternatives = alternatives[:]}}
    limited := lsystem.expand({axiom = "F", rules = rules[:]}, {iterations = 10, max_symbols = 16})
    defer lsystem.destroy_word(&limited)
    testing.expect_value(t, limited.error, lsystem.Expand_Error.Symbol_Limit)
    testing.expect_value(t, len(limited.word), 0)
}
