package tests

import quest "../packages/quest"
import "core:testing"

@(test)
quest_graph_activates_branches_and_preserves_early_work :: proc(t: ^testing.T) {
    letter_to_invite := [?]quest.Node_ID{2}
    invite_to_ready := [?]quest.Node_ID{6}
    crash_to_inspect := [?]quest.Node_ID{4}
    inspect_to_repair := [?]quest.Node_ID{5}
    repair_to_ready := [?]quest.Node_ID{6}
    ready_to_meeting := [?]quest.Node_ID{7}
    ready_requirements := [?]quest.Requirement{{node = 2}, {node = 5}}
    stamp_reward := [?]quest.Reward{{key = "stamp", amount = 1}}
    starts := [?]quest.Node_ID{1, 3}
    nodes := [?]quest.Node {
        {
            id = 1,
            key = "letter",
            title = "Deliver Niko's letter",
            kind = .Objective,
            objective = {kind = .Deliver, key = "first-letter", target = "iva"},
            successors = letter_to_invite[:],
            rewards = stamp_reward[:],
        },
        {
            id = 2,
            key = "invitation",
            title = "Deliver the invitation",
            kind = .Objective,
            objective = {kind = .Deliver, key = "invitation", target = "iva"},
            requirements = []quest.Requirement{{node = 1}},
            successors = invite_to_ready[:],
            rewards = stamp_reward[:],
        },
        {
            id = 3,
            key = "crash",
            title = "Ask Bojan about the landing",
            kind = .Objective,
            objective = {kind = .Talk, key = "crash-report", target = "bojan"},
            successors = crash_to_inspect[:],
        },
        {
            id = 4,
            key = "inspect",
            title = "Inspect the wing",
            kind = .Objective,
            objective = {kind = .Inspect, key = "bojan-wing"},
            requirements = []quest.Requirement{{node = 3}},
            successors = inspect_to_repair[:],
        },
        {
            id = 5,
            key = "repair",
            title = "Repair and verify the wing",
            kind = .Objective,
            objective = {kind = .Repair, key = "bojan-wing"},
            requirements = []quest.Requirement{{node = 4}},
            successors = repair_to_ready[:],
        },
        {
            id = 6,
            key = "ready",
            title = "The flight is ready",
            kind = .Gate,
            requirements = ready_requirements[:],
            successors = ready_to_meeting[:],
        },
        {
            id = 7,
            key = "meeting",
            title = "Attend the meeting",
            kind = .Objective,
            objective = {kind = .Talk, key = "awning-meeting"},
            requirements = []quest.Requirement{{node = 6}},
        },
    }
    definition := quest.Definition {
        id    = "two-island-test",
        nodes = nodes[:],
        start = starts[:],
    }
    state: quest.State
    _, initialized := quest.init(&state, &definition)
    testing.expect(t, initialized)
    testing.expect(t, quest.status(&state, &definition, 1) == .Active)
    testing.expect(t, quest.status(&state, &definition, 3) == .Active)

    _ = quest.publish(&state, &definition, {kind = .Talk, key = "crash-report", target = "bojan"})
    _ = quest.publish(&state, &definition, {kind = .Inspect, key = "bojan-wing"})
    _ = quest.publish(&state, &definition, {kind = .Repair, key = "bojan-wing"})
    testing.expect(t, quest.is_complete(&state, &definition, 5))
    testing.expect(t, quest.status(&state, &definition, 6) == .Locked)

    first := quest.publish(&state, &definition, {kind = .Deliver, key = "first-letter", target = "iva"})
    testing.expect(t, first.reward_count == 1)
    testing.expect(t, first.rewards[0].key == "stamp")
    second := quest.publish(&state, &definition, {kind = .Deliver, key = "invitation", target = "iva"})
    testing.expect(t, second.reward_count == 1)
    testing.expect(t, quest.is_complete(&state, &definition, 6))
    testing.expect(t, quest.status(&state, &definition, 7) == .Active)
}

@(test)
quest_graph_rewards_are_idempotent_and_repeatables_count :: proc(t: ^testing.T) {
    loop := [?]quest.Node_ID{1}
    reward := [?]quest.Reward{{key = "stamp", amount = 1}}
    starts := [?]quest.Node_ID{1}
    nodes := [?]quest.Node {
        {
            id = 1,
            key = "post",
            title = "Carry the post",
            kind = .Objective,
            objective = {kind = .Deliver, key = "post"},
            successors = loop[:],
            rewards = reward[:],
            repeatable = true,
        },
    }
    definition := quest.Definition {
        id    = "post-loop",
        nodes = nodes[:],
        start = starts[:],
    }
    state: quest.State
    _, initialized := quest.init(&state, &definition)
    testing.expect(t, initialized)

    first := quest.publish(&state, &definition, {kind = .Deliver, key = "post"})
    second := quest.publish(&state, &definition, {kind = .Deliver, key = "post"})
    testing.expect(t, first.reward_count == 1 && second.reward_count == 1)
    testing.expect(t, quest.completion_count(&state, &definition, 1) == 2)

    wrong := quest.publish(&state, &definition, {kind = .Deliver, key = "other-post"})
    testing.expect(t, wrong.reward_count == 0)
    testing.expect(t, quest.completion_count(&state, &definition, 1) == 2)
}

@(test)
quest_graph_validation_rejects_bad_catalogs :: proc(t: ^testing.T) {
    starts := [?]quest.Node_ID{1}
    unreachable := [?]quest.Node {
        {id = 1, key = "start", kind = .Objective, objective = {kind = .Visit, key = "west"}},
        {id = 2, key = "orphan", kind = .Objective, objective = {kind = .Visit, key = "east"}},
    }
    definition := quest.Definition {
        id    = "invalid",
        nodes = unreachable[:],
        start = starts[:],
    }
    testing.expect(t, !quest.validate(&definition))

    self_edge := [?]quest.Node_ID{1}
    bad_cycle := [?]quest.Node {
        {
            id = 1,
            key = "bad-cycle",
            kind = .Objective,
            objective = {kind = .Visit, key = "west"},
            successors = self_edge[:],
        },
    }
    definition.nodes = bad_cycle[:]
    testing.expect(t, !quest.validate(&definition))
}

@(test)
quest_graph_records_order_and_prefers_the_tracked_successor :: proc(t: ^testing.T) {
    first_successors := [?]quest.Node_ID{2}
    first_requirements := [?]quest.Requirement{{node = 1}}
    starts := [?]quest.Node_ID{1, 3}
    nodes := [?]quest.Node {
        {
            id = 1,
            key = "first",
            title = "First",
            kind = .Objective,
            objective = {kind = .Talk, key = "first"},
            successors = first_successors[:],
        },
        {
            id = 2,
            key = "second",
            title = "Second",
            kind = .Objective,
            objective = {kind = .Talk, key = "second"},
            requirements = first_requirements[:],
        },
        {
            id = 3,
            key = "parallel",
            title = "Parallel",
            kind = .Objective,
            objective = {kind = .Talk, key = "parallel"},
        },
    }
    definition := quest.Definition {
        id    = "tracking",
        nodes = nodes[:],
        start = starts[:],
    }
    state: quest.State
    _, initialized := quest.init(&state, &definition)
    testing.expect(t, initialized)
    testing.expect(t, quest.first_active(&state, &definition) == 1)
    testing.expect(
        t,
        quest.activation_sequence(&state, &definition, 1) < quest.activation_sequence(&state, &definition, 3),
    )

    _ = quest.publish(&state, &definition, {kind = .Talk, key = "first"})
    testing.expect(t, quest.completion_sequence(&state, &definition, 1) > 0)
    testing.expect(t, quest.preferred_tracking(&state, &definition, 1) == 2)

    _ = quest.publish(&state, &definition, {kind = .Talk, key = "second"})
    testing.expect(t, quest.preferred_tracking(&state, &definition, 2) == 3)
}
