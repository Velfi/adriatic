package tests

import dialogue "../packages/dialogue"
import "core:testing"

dialogue_text :: proc(_: ^dialogue.Context) -> string { return "Choose your course." }
dialogue_followup :: proc(_: ^dialogue.Context) -> string { return "The harbor answers." }
dialogue_speaker :: proc(_: ^dialogue.Context) -> string { return "Harbor master" }

Dialogue_Test_State :: struct {
    learned: bool,
}

learn_rumor :: proc(ctx: ^dialogue.Context) {
    state := cast(^Dialogue_Test_State)ctx.data
    state.learned = true
}

rumor_available :: proc(ctx: ^dialogue.Context) -> bool {
    state := cast(^Dialogue_Test_State)ctx.data
    return !state.learned
}

@(test)
dialogue_filters_choices_and_applies_effects :: proc(t: ^testing.T) {
    state := Dialogue_Test_State{}
    responses := []dialogue.Choice {
        dialogue.choice("Ask about the air lanes.", 1, rumor_available, learn_rumor),
        dialogue.choice("Leave the quay."),
    }
    followup := []dialogue.Choice{dialogue.choice("Return to the quay.")}
    nodes := []dialogue.Node {
        dialogue.node("greeting", dialogue_text, responses, dialogue_speaker),
        dialogue.node("news", dialogue_followup, followup, dialogue_speaker),
    }
    definition := dialogue.Definition {
        id         = "harbor",
        start_node = 0,
        nodes      = nodes,
    }
    conversation, opened := dialogue.open(&definition, dialogue.Context{data = &state, location_id = "porto_verde"})
    testing.expect(t, opened)
    testing.expect(t, dialogue.available_count(&conversation) == 2)
    testing.expect(t, dialogue.current(&conversation).speaker(&conversation.ctx) == "Harbor master")
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, state.learned)
    testing.expect(t, dialogue.current(&conversation).id == "news")
}

@(test)
dialogue_rejects_invalid_authored_targets :: proc(t: ^testing.T) {
    responses := []dialogue.Choice{dialogue.choice("Broken", 4)}
    nodes := []dialogue.Node{dialogue.node("start", dialogue_text, responses)}
    definition := dialogue.Definition {
        id         = "invalid",
        start_node = 0,
        nodes      = nodes,
    }
    _, opened := dialogue.open(&definition, {})
    testing.expect(t, !opened)
}

@(test)
dialogue_terminal_choice_ends_conversation :: proc(t: ^testing.T) {
    responses := []dialogue.Choice{dialogue.choice("Safe harbor.")}
    nodes := []dialogue.Node{dialogue.node("start", dialogue_text, responses)}
    definition := dialogue.Definition {
        id         = "terminal",
        start_node = 0,
        nodes      = nodes,
    }
    conversation, opened := dialogue.open(&definition, {})
    testing.expect(t, opened && dialogue.choose(&conversation, 0))
    testing.expect(t, conversation.ended && dialogue.current(&conversation) == nil)
}
