package story

import quest "../quest"

// Stable node IDs for the two-island campaign. String keys remain the durable
// authoring/debug identity; these compact IDs are resolved inside the catalog.
Quest_Node :: enum int {
    First_Letter = 1,
    First_Reply,
    Regatta_Invitation,
    Crash_Reported,
    Wing_Diagnosed,
    Wing_Patched,
    Repair_Verified,
    Ready_To_Fly,
    Regatta_Acceptance,
    Awning_Meeting,
    Post_Route,
    Magneto_Westbound,
    Magneto_Eastbound,
}

quest_node_id :: proc(node: Quest_Node) -> quest.Node_ID {
    return quest.Node_ID(node)
}

Quest_Catalog :: struct {
    magneto_out_successors:    [3]quest.Node_ID,
    first_letter_successors:   [1]quest.Node_ID,
    first_reply_successors:    [1]quest.Node_ID,
    invitation_successors:     [1]quest.Node_ID,
    crash_successors:          [1]quest.Node_ID,
    diagnosed_successors:      [1]quest.Node_ID,
    patched_successors:        [1]quest.Node_ID,
    repaired_successors:       [1]quest.Node_ID,
    ready_successors:          [1]quest.Node_ID,
    acceptance_successors:     [1]quest.Node_ID,
    meeting_successors:        [1]quest.Node_ID,
    post_successors:           [1]quest.Node_ID,
    magneto_back_requirements: [1]quest.Requirement,
    first_letter_requirements: [1]quest.Requirement,
    crash_requirements:        [1]quest.Requirement,
    first_reply_requirements:  [1]quest.Requirement,
    invitation_requirements:   [1]quest.Requirement,
    diagnosed_requirements:    [1]quest.Requirement,
    patched_requirements:      [1]quest.Requirement,
    repaired_requirements:     [1]quest.Requirement,
    ready_requirements:        [2]quest.Requirement,
    acceptance_requirements:   [1]quest.Requirement,
    meeting_requirements:      [1]quest.Requirement,
    post_requirements:         [1]quest.Requirement,
    stamp_reward:              [1]quest.Reward,
    starts:                    [1]quest.Node_ID,
    nodes:                     [13]quest.Node,
    definition:                quest.Definition,
}

init_quest_catalog :: proc(catalog: ^Quest_Catalog) {
    if catalog == nil do return
    catalog^ = {}

    first_letter := quest_node_id(.First_Letter)
    first_reply := quest_node_id(.First_Reply)
    invitation := quest_node_id(.Regatta_Invitation)
    crash := quest_node_id(.Crash_Reported)
    diagnosed := quest_node_id(.Wing_Diagnosed)
    patched := quest_node_id(.Wing_Patched)
    repaired := quest_node_id(.Repair_Verified)
    ready := quest_node_id(.Ready_To_Fly)
    acceptance := quest_node_id(.Regatta_Acceptance)
    meeting := quest_node_id(.Awning_Meeting)
    post := quest_node_id(.Post_Route)
    magneto_out := quest_node_id(.Magneto_Westbound)
    magneto_back := quest_node_id(.Magneto_Eastbound)

    catalog.magneto_out_successors = {magneto_back, first_letter, crash}
    catalog.first_letter_successors = {first_reply}
    catalog.first_reply_successors = {invitation}
    catalog.invitation_successors = {ready}
    catalog.crash_successors = {diagnosed}
    catalog.diagnosed_successors = {patched}
    catalog.patched_successors = {repaired}
    catalog.repaired_successors = {ready}
    catalog.ready_successors = {acceptance}
    catalog.acceptance_successors = {meeting}
    catalog.meeting_successors = {post}
    catalog.post_successors = {post}

    catalog.magneto_back_requirements = {{node = magneto_out}}
    catalog.first_letter_requirements = {{node = magneto_out}}
    catalog.crash_requirements = {{node = magneto_out}}
    catalog.first_reply_requirements = {{node = first_letter}}
    catalog.invitation_requirements = {{node = first_reply}}
    catalog.diagnosed_requirements = {{node = crash}}
    catalog.patched_requirements = {{node = diagnosed}}
    catalog.repaired_requirements = {{node = patched}}
    catalog.ready_requirements = {{node = invitation}, {node = repaired}}
    catalog.acceptance_requirements = {{node = ready}}
    catalog.meeting_requirements = {{node = acceptance}}
    catalog.post_requirements = {{node = meeting}}
    catalog.stamp_reward = {{key = "stamp", amount = 1}}
    catalog.starts = {magneto_out}

    catalog.nodes = {
        {
            id = first_letter,
            key = "first-letter",
            title = "Deliver Niko's sealed letter to Iva",
            instruction = "Carry Niko's sealed letter across the water and place it in Iva's hands.",
            location = "East island lighthouse",
            kind = .Objective,
            objective = {kind = .Deliver, key = "first-letter", target = "iva"},
            requirements = catalog.first_letter_requirements[:],
            successors = catalog.first_letter_successors[:],
            rewards = catalog.stamp_reward[:],
            requires_acceptance = true,
            hide_until_accepted = true,
        },
        {
            id = first_reply,
            key = "first-reply",
            title = "Return Iva's reply to Niko",
            instruction = "Keep Iva's reply sealed until it reaches Niko at the bakery.",
            location = "West island bakery",
            kind = .Objective,
            objective = {kind = .Deliver, key = "first-reply", target = "niko"},
            requirements = catalog.first_reply_requirements[:],
            successors = catalog.first_reply_successors[:],
            rewards = catalog.stamp_reward[:],
        },
        {
            id = invitation,
            key = "regatta-invitation",
            title = "Deliver Niko's regatta invitation",
            instruction = "Bring Niko's invitation to Iva before the regatta.",
            location = "East island lighthouse",
            kind = .Objective,
            objective = {kind = .Deliver, key = "regatta-invitation", target = "iva"},
            requirements = catalog.invitation_requirements[:],
            successors = catalog.invitation_successors[:],
            rewards = catalog.stamp_reward[:],
        },
        {
            id = crash,
            key = "crash-reported",
            title = "Ask Bojan about the landing",
            instruction = "Find Bojan and get the honest version of what happened to his aeroplane.",
            location = "West island airfield",
            kind = .Objective,
            objective = {kind = .Talk, key = "crash-reported", target = "bojan"},
            requirements = catalog.crash_requirements[:],
            successors = catalog.crash_successors[:],
            requires_acceptance = true,
            hide_until_accepted = true,
        },
        {
            id = diagnosed,
            key = "wing-diagnosed",
            title = "Inspect the torn wing",
            instruction = "Inspect Bojan's wing closely enough to identify what the repair needs.",
            location = "West island airfield",
            kind = .Objective,
            objective = {kind = .Inspect, key = "bojan-wing"},
            requirements = catalog.diagnosed_requirements[:],
            successors = catalog.diagnosed_successors[:],
        },
        {
            id = patched,
            key = "wing-patched",
            title = "Apply the canvas patch",
            instruction = "Stretch Bojan's canvas patch over the torn wing panel.",
            location = "West island airfield",
            kind = .Objective,
            objective = {kind = .Repair, key = "apply-wing-patch"},
            requirements = catalog.patched_requirements[:],
            successors = catalog.patched_successors[:],
        },
        {
            id = repaired,
            key = "repair-verified",
            title = "Verify the aircraft repair",
            instruction = "Turn the propeller and verify that the repaired wing is ready to fly.",
            location = "West island airfield",
            kind = .Objective,
            objective = {kind = .Repair, key = "verify-wing-repair"},
            requirements = catalog.repaired_requirements[:],
            successors = catalog.repaired_successors[:],
        },
        {
            id = ready,
            key = "ready-to-fly",
            title = "The invitation and aircraft are ready",
            kind = .Gate,
            requirements = catalog.ready_requirements[:],
            successors = catalog.ready_successors[:],
        },
        {
            id = acceptance,
            key = "regatta-acceptance",
            title = "Return Iva's regatta acceptance to Niko",
            instruction = "Bring Iva's regatta acceptance to Niko beneath the blue awning.",
            location = "West island bakery",
            kind = .Objective,
            objective = {kind = .Deliver, key = "regatta-acceptance", target = "niko"},
            requirements = catalog.acceptance_requirements[:],
            successors = catalog.acceptance_successors[:],
            rewards = catalog.stamp_reward[:],
        },
        {
            id = meeting,
            key = "awning-meeting",
            title = "Join Niko and Iva beneath the blue awning",
            instruction = "Visit Niko and Iva beneath the blue awning after Iva's arrival for the regatta.",
            location = "West island regatta",
            kind = .Objective,
            objective = {kind = .Talk, key = "awning-meeting"},
            requirements = catalog.meeting_requirements[:],
            successors = catalog.meeting_successors[:],
        },
        {
            id = post,
            key = "post-route",
            title = "Carry the island post",
            instruction = "Keep the letters, bread, and lamp glass moving between the two islands.",
            location = "Across the water",
            kind = .Objective,
            objective = {kind = .Deliver, key = "post-route"},
            requirements = catalog.post_requirements[:],
            successors = catalog.post_successors[:],
            rewards = catalog.stamp_reward[:],
            repeatable = true,
        },
        {
            id = magneto_out,
            key = "broken-magneto",
            title = "Bring Marta's broken magneto to Gerta",
            instruction = "Carry the cracked magneto across the water so Gerta can match it to her spare.",
            location = "West island airfield",
            kind = .Objective,
            objective = {kind = .Deliver, key = "broken-magneto", target = "gerta"},
            successors = catalog.magneto_out_successors[:],
            requires_acceptance = true,
            hide_until_accepted = true,
        },
        {
            id = magneto_back,
            key = "replacement-magneto",
            title = "Return Gerta's replacement magneto to Marta",
            instruction = "Keep the replacement magneto dry and bring it back to Marta at the east airfield.",
            location = "East island airfield",
            kind = .Objective,
            objective = {kind = .Deliver, key = "replacement-magneto", target = "marta"},
            requirements = catalog.magneto_back_requirements[:],
            rewards = catalog.stamp_reward[:],
        },
    }
    catalog.definition = {
        id    = "two-island-story",
        title = "Letters Across the Water",
        nodes = catalog.nodes[:],
        start = catalog.starts[:],
    }
}

ensure_quest_progress :: proc(state: ^State) -> bool {
    if state == nil do return false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)
    if state.quest.definition_id == catalog.definition.id && state.quest.node_count == len(catalog.definition.nodes) {
        projected: State
        _ = apply_quest_projection(&projected, &state.quest, &catalog)
        if projected.romance == state.romance &&
           projected.repair == state.repair &&
           projected.repeat_deliveries == state.repeat_deliveries {
            return apply_quest_projection(state, &state.quest, &catalog)
        }
    }

    legacy_romance := state.romance
    legacy_repair := state.repair
    legacy_repeats := state.repeat_deliveries
    _, initialized := quest.init(&state.quest, &catalog.definition)
    if !initialized do return false

    // Saves which had already begun either story branch have necessarily
    // visited the west island. Preserve that progress without making the new
    // introduction a retroactive blocker.
    if legacy_romance != .Unintroduced || legacy_repair != .Not_Seen {
        if quest.accept(&state.quest, &catalog.definition, quest_node_id(.Magneto_Westbound)) {
            _ = quest.publish(
                &state.quest,
                &catalog.definition,
                {kind = .Deliver, key = "broken-magneto", target = "gerta"},
            )
            _ = quest.publish(
                &state.quest,
                &catalog.definition,
                {kind = .Deliver, key = "replacement-magneto", target = "marta"},
            )
        }
    }

    if legacy_repair != .Not_Seen {
        _ = quest.accept(&state.quest, &catalog.definition, quest_node_id(.Crash_Reported))
        _ = quest.publish(&state.quest, &catalog.definition, {kind = .Talk, key = "crash-reported", target = "bojan"})
    }
    if legacy_repair == .Diagnosed || legacy_repair == .Patched || legacy_repair == .Repaired {
        _ = quest.publish(&state.quest, &catalog.definition, {kind = .Inspect, key = "bojan-wing"})
    }
    if legacy_repair == .Patched || legacy_repair == .Repaired {
        _ = quest.publish(&state.quest, &catalog.definition, {kind = .Repair, key = "apply-wing-patch"})
    }
    if legacy_repair == .Repaired {
        _ = quest.publish(&state.quest, &catalog.definition, {kind = .Repair, key = "verify-wing-repair"})
    }

    if legacy_romance != .Unintroduced {
        _ = quest.accept(&state.quest, &catalog.definition, quest_node_id(.First_Letter))
        _ = quest.publish(&state.quest, &catalog.definition, {kind = .Deliver, key = "first-letter", target = "iva"})
    }
    if legacy_romance == .Corresponding ||
       legacy_romance == .Invitation ||
       legacy_romance == .Meeting ||
       legacy_romance == .Together {
        _ = quest.publish(&state.quest, &catalog.definition, {kind = .Deliver, key = "first-reply", target = "niko"})
    }
    if legacy_romance == .Invitation || legacy_romance == .Meeting || legacy_romance == .Together {
        _ = quest.publish(
            &state.quest,
            &catalog.definition,
            {kind = .Deliver, key = "regatta-invitation", target = "iva"},
        )
    }
    if legacy_romance == .Meeting || legacy_romance == .Together {
        _ = quest.publish(
            &state.quest,
            &catalog.definition,
            {kind = .Deliver, key = "regatta-acceptance", target = "niko"},
        )
    }
    if legacy_romance == .Together {
        _ = quest.publish(&state.quest, &catalog.definition, {kind = .Talk, key = "awning-meeting"})
        for _ in 0 ..< legacy_repeats {
            _ = quest.publish(&state.quest, &catalog.definition, {kind = .Deliver, key = "post-route"})
        }
    }
    return apply_quest_projection(state, &state.quest, &catalog)
}

publish_quest_event :: proc(state: ^State, event: quest.Event) -> (quest.Update, bool) {
    update: quest.Update
    if state == nil || !ensure_quest_progress(state) do return update, false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)
    update = quest.publish(&state.quest, &catalog.definition, event)
    if !apply_quest_projection(state, &state.quest, &catalog) do return update, false
    return update, true
}

// apply_quest_projection is the compatibility boundary for the incremental
// migration. Existing dialogue and presentation may continue reading the
// compact stage enums while quest.State becomes the progression authority.
apply_quest_projection :: proc(state: ^State, graph_state: ^quest.State, catalog: ^Quest_Catalog) -> bool {
    if state == nil || graph_state == nil || catalog == nil do return false
    definition := &catalog.definition
    if graph_state.definition_id != definition.id do return false

    first_letter := quest.completion_count(graph_state, definition, quest_node_id(.First_Letter))
    first_reply := quest.completion_count(graph_state, definition, quest_node_id(.First_Reply))
    invitation := quest.completion_count(graph_state, definition, quest_node_id(.Regatta_Invitation))
    acceptance := quest.completion_count(graph_state, definition, quest_node_id(.Regatta_Acceptance))
    meeting := quest.completion_count(graph_state, definition, quest_node_id(.Awning_Meeting))
    crash := quest.completion_count(graph_state, definition, quest_node_id(.Crash_Reported))
    diagnosed := quest.completion_count(graph_state, definition, quest_node_id(.Wing_Diagnosed))
    patched := quest.completion_count(graph_state, definition, quest_node_id(.Wing_Patched))
    repaired := quest.completion_count(graph_state, definition, quest_node_id(.Repair_Verified))
    post := quest.completion_count(graph_state, definition, quest_node_id(.Post_Route))
    magneto_out := quest.completion_count(graph_state, definition, quest_node_id(.Magneto_Westbound))
    magneto_back := quest.completion_count(graph_state, definition, quest_node_id(.Magneto_Eastbound))

    switch {
    case meeting > 0:
        state.romance = .Together
    case acceptance > 0:
        state.romance = .Meeting
    case invitation > 0:
        state.romance = .Invitation
    case first_reply > 0:
        state.romance = .Corresponding
    case first_letter > 0:
        state.romance = .First_Letter
    case:
        state.romance = .Unintroduced
    }

    switch {
    case repaired > 0:
        state.repair = .Repaired
    case patched > 0:
        state.repair = .Patched
    case diagnosed > 0:
        state.repair = .Diagnosed
    case crash > 0:
        state.repair = .Crash_Reported
    case:
        state.repair = .Not_Seen
    }

    switch {
    case magneto_back > 0:
        state.airfield_errand = .Completed
    case magneto_out > 0:
        state.airfield_errand = .Eastbound
    case quest.status(graph_state, definition, quest_node_id(.Magneto_Westbound)) == .Active:
        state.airfield_errand = .Westbound
    case:
        state.airfield_errand = .Not_Offered
    }

    state.repeat_deliveries = post
    state.completed_deliveries = first_letter + first_reply + invitation + acceptance + post
    state.stamps_earned = state.completed_deliveries + magneto_back
    return true
}
