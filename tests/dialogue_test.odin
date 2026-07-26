package tests

import dialogue "../packages/dialogue"
import "core:testing"

dialogue_text :: proc(_: ^dialogue.Context) -> string { return "Choose your course." }
dialogue_followup :: proc(_: ^dialogue.Context) -> string { return "The harbor answers." }
dialogue_speaker :: proc(_: ^dialogue.Context) -> string { return "Harbor master" }

Dialogue_Test_State :: struct {
    learned: bool,
    entered: int,
    exited:  int,
}

learn_rumor :: proc(ctx: ^dialogue.Context) {
    state := cast(^Dialogue_Test_State)ctx.data
    state.learned = true
}

rumor_available :: proc(ctx: ^dialogue.Context) -> bool {
    state := cast(^Dialogue_Test_State)ctx.data
    return !state.learned
}

record_enter :: proc(ctx: ^dialogue.Context) {
    state := cast(^Dialogue_Test_State)ctx.data
    state.entered += 1
}

record_exit :: proc(ctx: ^dialogue.Context) {
    state := cast(^Dialogue_Test_State)ctx.data
    state.exited += 1
}

rich_line_spans := [?]dialogue.Text_Span {
    {text = "Incoming! ", effect = {color = {255, 255, 255, 255}, scale = 1, wave_amplitude = 3}},
    {
        text = "Take cover.",
        effect = {color = {255, 255, 255, 255}, scale = 1, characters_per_second = 10, reveal_delay = .5},
    },
}

rich_line :: proc(_: ^dialogue.Context) -> []dialogue.Text_Span {
    return rich_line_spans[:]
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

@(test)
dialogue_graph_supports_jump_history_and_lifecycle :: proc(t: ^testing.T) {
    state := Dialogue_Test_State{}
    terminal := []dialogue.Choice{dialogue.choice("Done")}
    nodes := []dialogue.Node {
        dialogue.rich_node("start", rich_line, terminal, enter_effect = record_enter, exit_effect = record_exit),
        dialogue.node("middle", dialogue_followup, terminal),
    }
    definition := dialogue.Definition {
        id    = "graph",
        nodes = nodes,
    }
    conversation, opened := dialogue.open(&definition, dialogue.Context{data = &state})
    testing.expect(t, opened && state.entered == 1)
    testing.expect(t, dialogue.find_node(&definition, "middle") == 1)
    testing.expect(t, dialogue.jump(&conversation, "middle"))
    testing.expect(t, state.exited == 1 && conversation.current_node == 1)
    testing.expect(t, dialogue.rewind(&conversation))
    testing.expect(t, conversation.current_node == 0 && state.entered == 2)
}

@(test)
dialogue_rich_text_effect_timing_is_deterministic :: proc(t: ^testing.T) {
    spans := rich_line(nil)
    testing.expect(t, len(spans) == 2)
    testing.expect(t, dialogue.reveal_glyph_count(spans[1].text) == 11)
    testing.expect(t, dialogue.visible_glyph_count(spans[1].effect, .25, 11) == 0)
    testing.expect(t, dialogue.visible_glyph_count(spans[1].effect, 1, 11) == 5)
    testing.expect(t, dialogue.rich_text_duration(spans) > 1.59)
}

@(test)
dialogue_auto_advance_supports_timed_and_terminal_nodes :: proc(t: ^testing.T) {
    nodes := []dialogue.Node {
        dialogue.rich_node("intro", rich_line, nil, auto_next_node = 1, auto_delay = .5),
        dialogue.rich_node("outro", rich_line, nil, auto_next_node = dialogue.no_next_node, auto_delay = .25),
    }
    definition := dialogue.Definition {
        id    = "auto",
        nodes = nodes,
    }
    conversation, opened := dialogue.open(&definition, {})
    testing.expect(t, opened)
    testing.expect(t, !dialogue.update(&conversation, .2))
    testing.expect(t, dialogue.update(&conversation, .3) && conversation.current_node == 1)
    testing.expect(t, dialogue.update(&conversation, .25) && conversation.ended)
    testing.expect(t, dialogue.restart(&conversation) && conversation.current_node == 0)
}
