package quest

// Product-local, presentation-neutral quest graph traversal.
//
// Definitions are immutable authored data. State contains only durable runtime
// progress, and Updates let the owning game translate progression into UI,
// audio, inventory, cinematics, and other product effects.

MAX_NODES :: 128
MAX_CHANGES :: 128
MAX_REWARDS :: 128

Node_ID :: distinct int
no_node :: Node_ID(-1)

Status :: enum u8 {
    Locked,
    Available,
    Active,
    Completed,
}

Node_Kind :: enum {
    Objective,
    Gate,
    Milestone,
    Reward,
}

Objective_Kind :: enum {
    None,
    Deliver,
    Visit,
    Talk,
    Inspect,
    Repair,
    Collect,
    Interact,
    Custom,
}

Requirement_Mode :: enum {
    All,
    Any,
}

Event :: struct {
    kind:   Objective_Kind,
    key:    string,
    target: string,
    amount: int,
}

Objective :: struct {
    kind:   Objective_Kind,
    key:    string,
    target: string,
    amount: int,
}

Requirement :: struct {
    node:             Node_ID,
    completion_count: int,
}

Reward :: struct {
    key:    string,
    amount: int,
}

Node :: struct {
    id:                  Node_ID,
    key:                 string,
    title:               string,
    instruction:         string,
    location:            string,
    kind:                Node_Kind,
    objective:           Objective,
    requirement_mode:    Requirement_Mode,
    requirements:        []Requirement,
    successors:          []Node_ID,
    rewards:             []Reward,
    repeatable:          bool,
    requires_acceptance: bool,
}

Definition :: struct {
    id:    string,
    title: string,
    nodes: []Node,
    start: []Node_ID,
}

State :: struct {
    definition_id:     string,
    node_count:        int,
    statuses:          [MAX_NODES]Status,
    completion_counts: [MAX_NODES]int,
    activated_at:      [MAX_NODES]u64,
    completed_at:      [MAX_NODES]u64,
    revision:          u64,
}

Update :: struct {
    activated:       [MAX_CHANGES]Node_ID,
    activated_count: int,
    completed:       [MAX_CHANGES]Node_ID,
    completed_count: int,
    rewards:         [MAX_REWARDS]Reward,
    reward_count:    int,
}

node_index :: proc(definition: ^Definition, id: Node_ID) -> int {
    if definition == nil do return -1
    for node, index in definition.nodes {
        if node.id == id do return index
    }
    return -1
}

find_node :: proc(definition: ^Definition, id: Node_ID) -> ^Node {
    index := node_index(definition, id)
    if index < 0 do return nil
    return &definition.nodes[index]
}

status :: proc(state: ^State, definition: ^Definition, id: Node_ID) -> Status {
    index := node_index(definition, id)
    if state == nil || index < 0 || index >= state.node_count do return .Locked
    return state.statuses[index]
}

completion_count :: proc(state: ^State, definition: ^Definition, id: Node_ID) -> int {
    index := node_index(definition, id)
    if state == nil || index < 0 || index >= state.node_count do return 0
    return state.completion_counts[index]
}

activation_sequence :: proc(state: ^State, definition: ^Definition, id: Node_ID) -> u64 {
    index := node_index(definition, id)
    if state == nil || index < 0 || index >= state.node_count do return 0
    return state.activated_at[index]
}

completion_sequence :: proc(state: ^State, definition: ^Definition, id: Node_ID) -> u64 {
    index := node_index(definition, id)
    if state == nil || index < 0 || index >= state.node_count do return 0
    return state.completed_at[index]
}

is_complete :: proc(state: ^State, definition: ^Definition, id: Node_ID) -> bool {
    return completion_count(state, definition, id) > 0
}

is_active :: proc(state: ^State, definition: ^Definition, id: Node_ID) -> bool {
    current := status(state, definition, id)
    return current == .Active || current == .Available
}

first_active :: proc(state: ^State, definition: ^Definition) -> Node_ID {
    if state == nil || definition == nil do return no_node
    result := no_node
    result_sequence: u64
    for &node in definition.nodes {
        if node.kind != .Objective || !is_active(state, definition, node.id) do continue
        sequence := activation_sequence(state, definition, node.id)
        if result == no_node || sequence < result_sequence {
            result = node.id
            result_sequence = sequence
        }
    }
    return result
}

preferred_tracking :: proc(state: ^State, definition: ^Definition, current: Node_ID) -> Node_ID {
    if state == nil || definition == nil do return no_node
    if is_active(state, definition, current) do return current
    if current_node := find_node(definition, current); current_node != nil {
        for successor in current_node.successors {
            node := find_node(definition, successor)
            if node != nil && node.kind == .Objective && is_active(state, definition, successor) {
                return successor
            }
        }
    }
    return first_active(state, definition)
}

requirements_met :: proc(state: ^State, definition: ^Definition, node: ^Node) -> bool {
    if state == nil || definition == nil || node == nil do return false
    if len(node.requirements) == 0 do return true
    if node.requirement_mode == .Any {
        for requirement in node.requirements {
            needed := max(requirement.completion_count, 1)
            if completion_count(state, definition, requirement.node) >= needed do return true
        }
        return false
    }
    for requirement in node.requirements {
        needed := max(requirement.completion_count, 1)
        if completion_count(state, definition, requirement.node) < needed do return false
    }
    return true
}

append_activated :: proc(update: ^Update, id: Node_ID) {
    if update == nil || update.activated_count >= len(update.activated) do return
    update.activated[update.activated_count] = id
    update.activated_count += 1
}

append_completed :: proc(update: ^Update, id: Node_ID) {
    if update == nil || update.completed_count >= len(update.completed) do return
    update.completed[update.completed_count] = id
    update.completed_count += 1
}

append_rewards :: proc(update: ^Update, rewards: []Reward) {
    if update == nil do return
    for reward in rewards {
        if update.reward_count >= len(update.rewards) do return
        update.rewards[update.reward_count] = reward
        update.reward_count += 1
    }
}

activate_index :: proc(state: ^State, definition: ^Definition, index: int, update: ^Update) -> bool {
    if state == nil || definition == nil || index < 0 || index >= state.node_count do return false
    node := &definition.nodes[index]
    if state.statuses[index] != .Locked || !requirements_met(state, definition, node) do return false
    state.statuses[index] = node.requires_acceptance ? .Available : .Active
    state.revision += 1
    state.activated_at[index] = state.revision
    append_activated(update, node.id)
    return true
}

complete_index :: proc(state: ^State, definition: ^Definition, index: int, update: ^Update) -> bool {
    if state == nil || definition == nil || index < 0 || index >= state.node_count do return false
    node := &definition.nodes[index]
    if state.statuses[index] != .Active do return false
    state.completion_counts[index] += 1
    state.statuses[index] = node.repeatable ? .Active : .Completed
    state.revision += 1
    state.completed_at[index] = state.revision
    append_completed(update, node.id)
    append_rewards(update, node.rewards)
    return true
}

refresh :: proc(state: ^State, definition: ^Definition, update: ^Update) {
    if state == nil || definition == nil do return
    changed := true
    for changed {
        changed = false
        for &node, index in definition.nodes {
            if state.statuses[index] != .Locked || !requirements_met(state, definition, &node) do continue

            reachable := false
            for start in definition.start {
                if start == node.id {
                    reachable = true
                    break
                }
            }
            if !reachable {
                for &source, source_index in definition.nodes {
                    if state.completion_counts[source_index] == 0 do continue
                    for successor in source.successors {
                        if successor == node.id {
                            reachable = true
                            break
                        }
                    }
                    if reachable do break
                }
            }
            if !reachable do continue
            if !activate_index(state, definition, index, update) do continue
            changed = true
            if node.kind == .Gate || node.kind == .Milestone || node.kind == .Reward {
                _ = complete_index(state, definition, index, update)
            }
        }
    }
}

init :: proc(state: ^State, definition: ^Definition) -> (Update, bool) {
    update: Update
    if state == nil || !validate(definition) do return update, false
    state^ = {
        definition_id = definition.id,
        node_count    = len(definition.nodes),
    }
    refresh(state, definition, &update)
    return update, true
}

accept :: proc(state: ^State, definition: ^Definition, id: Node_ID) -> bool {
    index := node_index(definition, id)
    if state == nil || index < 0 || state.statuses[index] != .Available do return false
    state.statuses[index] = .Active
    state.revision += 1
    return true
}

matches :: proc(objective: Objective, event: Event) -> bool {
    if objective.kind == .None || objective.kind != event.kind do return false
    if objective.key != event.key do return false
    if len(objective.target) > 0 && objective.target != event.target do return false
    return max(event.amount, 1) >= max(objective.amount, 1)
}

publish :: proc(state: ^State, definition: ^Definition, event: Event) -> Update {
    update: Update
    if state == nil || definition == nil || state.definition_id != definition.id do return update
    for &node, index in definition.nodes {
        if state.statuses[index] != .Active || !matches(node.objective, event) do continue
        _ = complete_index(state, definition, index, &update)
    }
    refresh(state, definition, &update)
    return update
}

validate :: proc(definition: ^Definition) -> bool {
    if definition == nil || len(definition.id) == 0 do return false
    if len(definition.nodes) == 0 || len(definition.nodes) > MAX_NODES do return false
    if len(definition.start) == 0 do return false

    for &node, index in definition.nodes {
        if node.id == no_node || len(node.key) == 0 do return false
        if node.kind == .Objective && node.objective.kind == .None do return false
        if node.kind == .Gate && len(node.requirements) == 0 do return false
        if node.repeatable && node.requires_acceptance do return false
        for prior in definition.nodes[:index] {
            if prior.id == node.id || prior.key == node.key do return false
        }
        for requirement in node.requirements {
            if requirement.completion_count < 0 || node_index(definition, requirement.node) < 0 do return false
        }
        for successor in node.successors {
            if node_index(definition, successor) < 0 do return false
            if successor == node.id && !node.repeatable do return false
        }
        for reward in node.rewards {
            if len(reward.key) == 0 || reward.amount == 0 do return false
        }
    }
    for start in definition.start {
        if node_index(definition, start) < 0 do return false
    }

    reachable: [MAX_NODES]bool
    changed := true
    for changed {
        changed = false
        for start in definition.start {
            index := node_index(definition, start)
            if !reachable[index] {
                reachable[index] = true
                changed = true
            }
        }
        for &node, index in definition.nodes {
            if !reachable[index] do continue
            for successor in node.successors {
                successor_index := node_index(definition, successor)
                if !reachable[successor_index] {
                    reachable[successor_index] = true
                    changed = true
                }
            }
        }
    }
    for _, index in definition.nodes {
        if !reachable[index] do return false
    }

    // Every strongly connected component must contain an explicitly repeatable
    // node. This permits authored loops while rejecting accidental cycles.
    connected: [MAX_NODES][MAX_NODES]bool
    for &node, index in definition.nodes {
        for successor in node.successors {
            successor_index := node_index(definition, successor)
            connected[index][successor_index] = true
        }
    }
    for middle in 0 ..< len(definition.nodes) {
        for source in 0 ..< len(definition.nodes) {
            if !connected[source][middle] do continue
            for destination in 0 ..< len(definition.nodes) {
                if connected[middle][destination] {
                    connected[source][destination] = true
                }
            }
        }
    }
    for index in 0 ..< len(definition.nodes) {
        if !connected[index][index] do continue
        has_repeatable_boundary := false
        for candidate in 0 ..< len(definition.nodes) {
            if connected[index][candidate] && connected[candidate][index] && definition.nodes[candidate].repeatable {
                has_repeatable_boundary = true
                break
            }
        }
        if !has_repeatable_boundary do return false
    }
    return true
}
