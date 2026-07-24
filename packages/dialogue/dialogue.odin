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
Condition_Proc :: proc(ctx: ^Context) -> bool
Effect_Proc :: proc(ctx: ^Context)

Choice :: struct {
    text:      string,
    next_node: int,
    condition: Condition_Proc,
    effect:    Effect_Proc,
}

Node :: struct {
    id:      string,
    speaker: Text_Proc,
    text:    Text_Proc,
    choices: []Choice,
}

Definition :: struct {
    id:         string,
    start_node: int,
    nodes:      []Node,
}

Conversation :: struct {
    definition:   ^Definition,
    ctx:          Context,
    current_node: int,
    ended:        bool,
}

// no_next_node marks a terminal response. Node indices are stable indices in
// Definition.nodes, which keeps authored data simple and avoids string-keyed
// maps in the runtime.
no_next_node :: -1

always_available :: proc(_: ^Context) -> bool { return true }
no_effect :: proc(_: ^Context) {  }
empty_text :: proc(_: ^Context) -> string { return "" }

choice :: proc(
    text: string,
    next_node := no_next_node,
    condition: Condition_Proc = always_available,
    effect: Effect_Proc = no_effect,
) -> Choice {
    return {text = text, next_node = next_node, condition = condition, effect = effect}
}

node :: proc(id: string, text: Text_Proc, choices: []Choice, speaker: Text_Proc = empty_text) -> Node {
    return {id = id, speaker = speaker, text = text, choices = choices}
}

// validate checks the same authoring invariants as the source system. It is
// intentionally side-effect free so tools and tests can validate catalogs
// before opening a conversation.
validate :: proc(definition: ^Definition) -> bool {
    if definition == nil || len(definition.id) == 0 do return false
    if len(definition.nodes) == 0 do return false
    if definition.start_node < 0 || definition.start_node >= len(definition.nodes) do return false
    for &current, index in definition.nodes {
        if len(current.id) == 0 || current.speaker == nil || current.text == nil do return false
        if len(current.choices) == 0 do return false
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
    return {definition = definition, ctx = ctx, current_node = definition.start_node}, true
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
    response.effect(&conversation.ctx)
    if response.next_node == no_next_node {
        conversation.ended = true
        return true
    }
    conversation.current_node = response.next_node
    if available_count(conversation) == 0 {
        conversation.ended = true
        return false
    }
    return true
}
