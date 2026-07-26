package dialogue

// A small, presentation-neutral branching conversation runtime.
//
// This is the reusable part of ArchipelagoGame's DialogueSystem: authored
// nodes provide text and choices, conditions decide which choices are visible,
// and effects update the owning game's state. Rendering, input, persistence,
// and the concrete game/session context remain the caller's responsibility.

Context :: struct {
    data:           rawptr,
    location_id:    string,
    resident_index: int,
}

Text_Proc :: proc(ctx: ^Context) -> string
Rich_Text_Proc :: proc(ctx: ^Context) -> []Text_Span
Condition_Proc :: proc(ctx: ^Context) -> bool
Effect_Proc :: proc(ctx: ^Context)

// Text effects are authored per span and interpreted by the presentation
// layer. Values are deliberately renderer-neutral and match the effects used
// by Zelda Engine's text renderer.
Text_Effect :: struct {
    color:                            [4]u8,
    scale:                            f32,
    offset_x, offset_y:               f32,
    letter_spacing:                   f32,
    bold, italic, underline:          bool,
    shadow_color:                     [4]u8,
    shadow_offset_x, shadow_offset_y: f32,
    wave_amplitude:                   f32,
    wave_frequency:                   f32,
    wave_speed:                       f32,
    shake:                            f32,
    pulse_amount:                     f32,
    pulse_speed:                      f32,
    drift_x, drift_y:                 f32,
    characters_per_second:            f32,
    reveal_delay:                     f32,
}

Text_Span :: struct {
    text:   string,
    effect: Text_Effect,
}

Choice :: struct {
    text:      string,
    next_node: int,
    condition: Condition_Proc,
    effect:    Effect_Proc,
}

Node :: struct {
    id:             string,
    speaker:        Text_Proc,
    text:           Text_Proc,
    rich_text:      Rich_Text_Proc,
    choices:        []Choice,
    enter_effect:   Effect_Proc,
    exit_effect:    Effect_Proc,
    auto_next_node: int,
    auto_delay:     f32,
}

Definition :: struct {
    id:         string,
    start_node: int,
    nodes:      []Node,
}

Conversation :: struct {
    definition:    ^Definition,
    ctx:           Context,
    current_node:  int,
    ended:         bool,
    elapsed:       f32,
    revision:      u64,
    history:       [128]int,
    history_count: int,
}

// no_next_node marks a terminal response. Node indices are stable indices in
// Definition.nodes, which keeps authored data simple and avoids string-keyed
// maps in the runtime.
no_next_node :: -1
no_auto_node :: -2

always_available :: proc(_: ^Context) -> bool { return true }
no_effect :: proc(_: ^Context) {  }
empty_text :: proc(_: ^Context) -> string { return "" }
empty_rich_text :: proc(_: ^Context) -> []Text_Span { return nil }

text_effect :: proc(color := [4]u8{255, 255, 255, 255}, scale: f32 = 1) -> Text_Effect {
    return {color = color, scale = scale}
}

text_span :: proc(text: string, effect: Text_Effect) -> Text_Span {
    return {text = text, effect = effect}
}

reveal_glyph_count :: proc(text: string) -> int {
    count := 0
    for rune in text {
        if rune != '\n' do count += 1
    }
    return count
}

visible_glyph_count :: proc(effect: Text_Effect, elapsed: f32, glyph_count: int) -> int {
    if effect.characters_per_second <= 0 do return glyph_count
    if elapsed <= effect.reveal_delay do return 0
    return clamp(int((elapsed - effect.reveal_delay) * effect.characters_per_second), 0, glyph_count)
}

span_duration :: proc(effect: Text_Effect, glyph_count: int) -> f32 {
    if effect.characters_per_second <= 0 do return 0
    return max(effect.reveal_delay, 0) + f32(glyph_count) / effect.characters_per_second
}

rich_text_duration :: proc(spans: []Text_Span) -> f32 {
    duration: f32
    for span in spans {
        duration += span_duration(span.effect, reveal_glyph_count(span.text))
    }
    return duration
}

choice :: proc(
    text: string,
    next_node := no_next_node,
    condition: Condition_Proc = always_available,
    effect: Effect_Proc = no_effect,
) -> Choice {
    return {text = text, next_node = next_node, condition = condition, effect = effect}
}

node :: proc(id: string, text: Text_Proc, choices: []Choice, speaker: Text_Proc = empty_text) -> Node {
    return {
        id = id,
        speaker = speaker,
        text = text,
        rich_text = empty_rich_text,
        choices = choices,
        enter_effect = no_effect,
        exit_effect = no_effect,
        auto_next_node = no_auto_node,
    }
}

rich_node :: proc(
    id: string,
    rich_text: Rich_Text_Proc,
    choices: []Choice,
    speaker: Text_Proc = empty_text,
    enter_effect: Effect_Proc = no_effect,
    exit_effect: Effect_Proc = no_effect,
    auto_next_node := no_auto_node,
    auto_delay: f32 = 0,
) -> Node {
    return {
        id = id,
        speaker = speaker,
        text = empty_text,
        rich_text = rich_text,
        choices = choices,
        enter_effect = enter_effect,
        exit_effect = exit_effect,
        auto_next_node = auto_next_node,
        auto_delay = auto_delay,
    }
}

// validate checks the same authoring invariants as the source system. It is
// intentionally side-effect free so tools and tests can validate catalogs
// before opening a conversation.
validate :: proc(definition: ^Definition) -> bool {
    if definition == nil || len(definition.id) == 0 do return false
    if len(definition.nodes) == 0 do return false
    if definition.start_node < 0 || definition.start_node >= len(definition.nodes) do return false
    for &current, index in definition.nodes {
        if len(current.id) == 0 ||
           current.speaker == nil ||
           current.text == nil ||
           current.rich_text == nil ||
           current.enter_effect == nil ||
           current.exit_effect == nil {
            return false
        }
        if len(current.choices) == 0 && current.auto_next_node == no_auto_node do return false
        if current.auto_delay < 0 do return false
        if current.auto_next_node != no_auto_node &&
           current.auto_next_node != no_next_node &&
           (current.auto_next_node < 0 || current.auto_next_node >= len(definition.nodes)) {
            return false
        }
        for &response in current.choices {
            if len(response.text) == 0 || response.condition == nil || response.effect == nil do return false
            if response.next_node != no_next_node &&
               (response.next_node < 0 || response.next_node >= len(definition.nodes)) {
                return false
            }
        }
        // Duplicate IDs make authored diagnostics and tooling ambiguous even
        // though transitions use indices.
        for prior in definition.nodes[:index] {
            if prior.id == current.id do return false
        }
    }
    return true
}

open :: proc(definition: ^Definition, ctx: Context) -> (Conversation, bool) {
    if !validate(definition) do return {}, false
    conversation := Conversation {
        definition   = definition,
        ctx          = ctx,
        current_node = definition.start_node,
    }
    definition.nodes[definition.start_node].enter_effect(&conversation.ctx)
    return conversation, true
}

current :: proc(conversation: ^Conversation) -> ^Node {
    if conversation == nil || conversation.definition == nil || conversation.ended do return nil
    return &conversation.definition.nodes[conversation.current_node]
}

is_available :: proc(response: ^Choice, ctx: ^Context) -> bool {
    return response != nil && response.condition != nil && response.condition(ctx)
}

available_count :: proc(conversation: ^Conversation) -> int {
    current_node := current(conversation)
    if current_node == nil do return 0
    count := 0
    for &response in current_node.choices {
        if is_available(&response, &conversation.ctx) do count += 1
    }
    return count
}

available_at :: proc(conversation: ^Conversation, available_index: int) -> ^Choice {
    current_node := current(conversation)
    if current_node == nil || available_index < 0 do return nil
    visible_index := 0
    for &response in current_node.choices {
        if !is_available(&response, &conversation.ctx) do continue
        if visible_index == available_index do return &response
        visible_index += 1
    }
    return nil
}

// choose selects an authored choice by its visible index, matching how a UI
// normally presents filtered responses. It returns false for stale/hidden
// choices, terminal conversations, or catalogs that reach an empty node.
choose :: proc(conversation: ^Conversation, available_index: int) -> bool {
    if conversation == nil || conversation.ended do return false
    response := available_at(conversation, available_index)
    if response == nil do return false
    source := current(conversation)
    source.exit_effect(&conversation.ctx)
    response.effect(&conversation.ctx)
    if response.next_node == no_next_node {
        conversation.ended = true
        conversation.revision += 1
        return true
    }
    transition(conversation, response.next_node, record_history = true, run_exit = false)
    destination := current(conversation)
    if available_count(conversation) == 0 && (destination == nil || destination.auto_next_node == no_auto_node) {
        conversation.ended = true
        return false
    }
    return true
}

find_node :: proc(definition: ^Definition, id: string) -> int {
    if definition == nil do return no_next_node
    for node, index in definition.nodes {
        if node.id == id do return index
    }
    return no_next_node
}

transition :: proc(conversation: ^Conversation, target: int, record_history := true, run_exit := true) -> bool {
    if conversation == nil || conversation.definition == nil || conversation.ended do return false
    if target == no_next_node {
        if run_exit {
            if node := current(conversation); node != nil do node.exit_effect(&conversation.ctx)
        }
        conversation.ended = true
        conversation.revision += 1
        return true
    }
    if target < 0 || target >= len(conversation.definition.nodes) do return false
    if run_exit {
        if node := current(conversation); node != nil do node.exit_effect(&conversation.ctx)
    }
    if record_history && conversation.history_count < len(conversation.history) {
        conversation.history[conversation.history_count] = conversation.current_node
        conversation.history_count += 1
    }
    conversation.current_node = target
    conversation.elapsed = 0
    conversation.revision += 1
    conversation.definition.nodes[target].enter_effect(&conversation.ctx)
    return true
}

jump :: proc(conversation: ^Conversation, node_id: string) -> bool {
    if conversation == nil do return false
    target := find_node(conversation.definition, node_id)
    if target == no_next_node do return false
    return transition(conversation, target)
}

rewind :: proc(conversation: ^Conversation) -> bool {
    if conversation == nil || conversation.ended || conversation.history_count == 0 do return false
    conversation.history_count -= 1
    return transition(conversation, conversation.history[conversation.history_count], record_history = false)
}

update :: proc(conversation: ^Conversation, delta_seconds: f32) -> bool {
    node := current(conversation)
    if node == nil do return false
    conversation.elapsed += max(delta_seconds, 0)
    if node.auto_next_node != no_auto_node && conversation.elapsed >= node.auto_delay {
        return transition(conversation, node.auto_next_node)
    }
    return false
}

restart :: proc(conversation: ^Conversation) -> bool {
    if conversation == nil || conversation.definition == nil do return false
    if node := current(conversation); node != nil do node.exit_effect(&conversation.ctx)
    conversation.current_node = conversation.definition.start_node
    conversation.ended = false
    conversation.elapsed = 0
    conversation.history_count = 0
    conversation.revision += 1
    conversation.definition.nodes[conversation.current_node].enter_effect(&conversation.ctx)
    return true
}
