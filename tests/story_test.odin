package tests

import dialogue "../packages/dialogue"
import quest "../packages/quest"
import story "../packages/story"
import tarot "../packages/tarot"
import "core:testing"

repair_aircraft :: proc(t: ^testing.T, state: ^story.State) {
    testing.expect(t, story.report_crash(state))
    testing.expect(t, story.diagnose_crash(state))
    testing.expect(t, state.has_wing_patch)
    testing.expect(t, story.apply_wing_patch(state))
    testing.expect(t, !state.has_wing_patch)
    testing.expect(t, story.verify_repair(state))
}

complete_current_delivery :: proc(t: ^testing.T, state: ^story.State, recipient: story.Resident) {
    testing.expect(t, story.complete_delivery(state, recipient))
}

complete_airfield_intro :: proc(t: ^testing.T, state: ^story.State) {
    testing.expect(t, story.accept_airfield_errand(state))
    testing.expect(t, story.handoff_broken_magneto(state))
    testing.expect(t, story.return_replacement_magneto(state))
}

expect_choice_texts :: proc(t: ^testing.T, actual: []dialogue.Choice, expected: []string) {
    testing.expect(t, len(actual) == len(expected))
    for choice, index in actual {
        testing.expect(t, choice.text == expected[index])
    }
}

@(test)
island_post_is_always_available_and_alternates_between_islands :: proc(t: ^testing.T) {
    state: story.State

    testing.expect(t, story.begin_post_delivery(&state))
    testing.expect(t, state.romance == .Unintroduced)
    testing.expect(t, state.delivery.kind == .Repeat_Eastbound)
    testing.expect(t, state.delivery.origin == .West && state.delivery.destination == .East)
    complete_current_delivery(t, &state, .Lena)
    testing.expect(t, state.repeat_deliveries == 1 && state.stamps_earned == 1)

    testing.expect(t, story.begin_post_delivery(&state))
    testing.expect(t, state.delivery.kind == .Repeat_Westbound)
    testing.expect(t, state.delivery.origin == .East && state.delivery.destination == .West)
    complete_current_delivery(t, &state, .Toma)
    testing.expect(t, state.repeat_deliveries == 2 && state.stamps_earned == 2)

    // The independent postal route does not consume or advance the authored
    // correspondence storyline.
    complete_airfield_intro(t, &state)
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.kind == .First_Letter)
}

@(test)
two_island_story_advances_on_completion_and_becomes_repeatable :: proc(t: ^testing.T) {
    state: story.State

    complete_airfield_intro(t, &state)
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.romance == .Unintroduced)
    testing.expect(t, state.delivery.kind == .First_Letter)
    testing.expect(t, state.delivery.subject == "A recipe for a clear morning")
    testing.expect(t, state.delivery.origin == .West && state.delivery.destination == .East)
    complete_current_delivery(t, &state, .Iva)
    testing.expect(t, state.romance == .First_Letter)

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.romance == .First_Letter)
    testing.expect(t, state.delivery.kind == .First_Reply)
    testing.expect(t, state.delivery.subject == "The lighthouse keeper's reply")
    testing.expect(t, state.delivery.origin == .East && state.delivery.destination == .West)
    complete_current_delivery(t, &state, .Niko)
    testing.expect(t, state.romance == .Corresponding)

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.romance == .Corresponding)
    testing.expect(t, state.delivery.kind == .Regatta_Invitation)
    testing.expect(t, state.delivery.subject == "An invitation for the regatta")
    complete_current_delivery(t, &state, .Iva)
    testing.expect(t, state.romance == .Invitation)
    testing.expect(t, !story.begin_delivery(&state))

    repair_aircraft(t, &state)
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.romance == .Invitation)
    testing.expect(t, state.delivery.kind == .Regatta_Acceptance)
    testing.expect(t, state.delivery.subject == "Meet me beneath the blue awning")
    complete_current_delivery(t, &state, .Niko)
    testing.expect(t, state.romance == .Meeting)
    testing.expect(t, !story.begin_delivery(&state))
    testing.expect(t, state.stamps_earned == 5)

    testing.expect(t, story.complete_meeting(&state))
    testing.expect(t, state.romance == .Together)

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.kind == .Repeat_Eastbound)
    testing.expect(t, state.delivery.subject == "Bread, postcards, and one pressed flower")
    complete_current_delivery(t, &state, .Lena)
    testing.expect(t, state.repeat_deliveries == 1 && state.stamps_earned == 6)

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.kind == .Repeat_Westbound)
    testing.expect(t, state.delivery.subject == "Lamp glass and a note for supper")
    complete_current_delivery(t, &state, .Toma)
    testing.expect(t, state.repeat_deliveries == 2 && state.stamps_earned == 7)
}

@(test)
early_repair_is_preserved_as_preparedness :: proc(t: ^testing.T) {
    state: story.State
    complete_airfield_intro(t, &state)
    repair_aircraft(t, &state)

    testing.expect(t, story.begin_delivery(&state))
    complete_current_delivery(t, &state, .Iva)
    testing.expect(t, story.begin_delivery(&state))
    complete_current_delivery(t, &state, .Niko)
    testing.expect(t, story.begin_delivery(&state))
    complete_current_delivery(t, &state, .Iva)

    testing.expect(t, state.romance == .Invitation && state.repair == .Repaired)
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.kind == .Regatta_Acceptance)
}

@(test)
story_rejects_wrong_recipient_invalid_kind_and_out_of_order_repair :: proc(t: ^testing.T) {
    state: story.State
    testing.expect(t, !story.begin_delivery(&state))
    testing.expect(t, story.accept_airfield_errand(&state))
    testing.expect(t, story.handoff_broken_magneto(&state))
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, !story.complete_delivery(&state, .Niko))
    testing.expect(t, state.delivery.active)
    testing.expect(t, !story.diagnose_crash(&state))
    testing.expect(t, !story.apply_wing_patch(&state))
    testing.expect(t, !story.verify_repair(&state))
    testing.expect(t, !story.complete_meeting(&state))

    invalid := story.State {
        delivery = {active = true, kind = .None, to = .Iva},
    }
    testing.expect(t, !story.complete_delivery(&invalid, .Iva))
    testing.expect(t, invalid.delivery.active)
}

@(test)
character_dialogue_catalog_is_valid_and_meeting_finishes_through_dialogue :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    testing.expect(t, dialogue.validate(&catalog.niko))
    testing.expect(t, dialogue.validate(&catalog.iva))
    testing.expect(t, dialogue.validate(&catalog.bojan))
    testing.expect(t, dialogue.validate(&catalog.zora))
    testing.expect(t, dialogue.validate(&catalog.vesna))
    testing.expect(t, dialogue.validate(&catalog.petar))
    testing.expect(t, dialogue.validate(&catalog.anica))
    testing.expect(t, dialogue.validate(&catalog.toma))
    testing.expect(t, dialogue.validate(&catalog.lena))
    expect_choice_texts(
        t,
        catalog.niko_root_choices[:],
        []string {
            "Give Niko Iva's reply.",
            "Give Niko Iva's regatta acceptance.",
            "I'll carry your sealed letter to Iva.",
            "I'll carry your regatta invitation to Iva.",
            "Stay under the awning.",
            "I'll leave you to your work.",
        },
    )
    expect_choice_texts(
        t,
        catalog.niko_reaction_choices[:],
        []string{"You could try to look a little less pleased.", "The letter stayed sealed."},
    )
    expect_choice_texts(t, catalog.niko_warm_choices[:], []string{"Safe crossing, Niko."})
    expect_choice_texts(t, catalog.niko_discreet_choices[:], []string{"Not a word from me."})
    expect_choice_texts(
        t,
        catalog.meeting_choices[:],
        []string{"The awning suits you both.", "I saw only an ordinary arrival."},
    )
    expect_choice_texts(t, catalog.meeting_finish_choices[:], []string{"Enjoy the regatta."})
    expect_choice_texts(
        t,
        catalog.iva_root_choices[:],
        []string {
            "Give Iva Niko's sealed letter.",
            "Give Iva Niko's regatta invitation.",
            "I'll carry your reply to Niko.",
            "I'll carry your regatta acceptance to Niko.",
            "I'll leave you to tend the lamp.",
        },
    )
    expect_choice_texts(
        t,
        catalog.iva_reaction_choices[:],
        []string{"The lamp seems especially cheerful.", "The letter stayed sealed."},
    )
    expect_choice_texts(t, catalog.iva_warm_choices[:], []string{"Keep the light burning, Iva."})
    expect_choice_texts(t, catalog.iva_discreet_choices[:], []string{"Not a word from me."})
    expect_choice_texts(
        t,
        catalog.bojan_choices[:],
        []string {
            "I saw the whole thing.",
            "Let's inspect the wing.",
            "Apply the canvas patch.",
            "Turn the propeller.",
            "I'll leave you to it.",
        },
    )
    expect_choice_texts(
        t,
        catalog.zora_choices[:],
        []string {
            "Just tell me which way the wind is blowing today.",
            "Where I came from, where I am, and where I might go.",
            "I have time. Lay out the full cross.",
            "Another time, grazie.",
        },
    )
    expect_choice_texts(t, catalog.zora_return_choices[:], []string{"Enough cards. I'll watch the real sky."})

    state := story.State {
        romance = .Meeting,
        repair  = .Repaired,
    }
    conversation, opened := dialogue.open(
        &catalog.niko,
        {data = rawptr(&state), location_id = "west_island", resident_index = int(story.Resident.Niko)},
    )
    testing.expect(t, opened)
    testing.expect(t, dialogue.available_count(&conversation) == 2)
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, dialogue.current(&conversation).id == "meeting-iva")
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, dialogue.current(&conversation).id == "meeting-niko")
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, conversation.ended)
    testing.expect(t, state.romance == .Together)
}

@(test)
zora_deals_an_actual_selected_tarot_layout :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state: story.State
    conversation, opened := dialogue.open(
        &catalog.zora,
        {data = rawptr(&state), location_id = "east_island", resident_index = int(story.Resident.Zora)},
    )
    testing.expect(t, opened)
    testing.expect(t, dialogue.choose(&conversation, 2))
    testing.expect(t, state.tarot_readings == 1)
    testing.expect(t, state.tarot_layout.spread == .Celtic_Cross)
    testing.expect(t, state.tarot_layout.count == 10)
    testing.expect(t, state.tarot_last_moment != 0)
    testing.expect(t, dialogue.current(&conversation).id == "zora-reading")
    reading := dialogue.current(&conversation).text(&conversation.ctx)
    testing.expect(t, len(reading) > len(tarot.card_name(state.tarot_layout.placements[0].card)))

    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, conversation.ended)

    same_moment, reopened := dialogue.open(
        &catalog.zora,
        {data = rawptr(&state), location_id = "east_island", resident_index = int(story.Resident.Zora)},
    )
    testing.expect(t, reopened)
    testing.expect(t, dialogue.available_count(&same_moment) == 1)

    state.romance = .First_Letter
    next_moment, opened_again := dialogue.open(
        &catalog.zora,
        {data = rawptr(&state), location_id = "east_island", resident_index = int(story.Resident.Zora)},
    )
    testing.expect(t, opened_again)
    testing.expect(t, dialogue.available_count(&next_moment) == 4)
}

@(test)
dialogue_text_and_choices_follow_story_and_repair_state :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state: story.State
    ctx := dialogue.Context {
        data = rawptr(&state),
    }

    testing.expect(
        t,
        story.niko_text(&ctx) == "La lamp on the east island blinks twice avant alba. Iva watches while my ovens warm.",
    )
    testing.expect(
        t,
        story.bojan_text(&ctx) ==
        "La landing was perfekt. The ground arrived troppo early. You saw zero complication.",
    )
    testing.expect(
        t,
        story.zora_text(&ctx) ==
        "Close la shutter, piccolo courier. The bura already mixes enough. Le cards do not command il mare; they show only where the vento turns.",
    )

    state.romance = .Invitation
    testing.expect(
        t,
        story.iva_text(&ctx) == "Io can respond to Niko, but la broken wing cannot carry me. Nema regatta yet.",
    )
    repair_aircraft(t, &state)
    testing.expect(
        t,
        story.iva_text(&ctx) ==
        "Tu repaired Bojan's aeroplano before io needed it. Grazie; now you can carry la regatta acceptance.",
    )
    testing.expect(
        t,
        story.bojan_text(&ctx) == "L'aereo is ready for Iva. Io even cleaned the seat that is not mine.",
    )

    iva_conversation, opened := dialogue.open(
        &catalog.iva,
        {data = rawptr(&state), location_id = "east_island", resident_index = int(story.Resident.Iva)},
    )
    testing.expect(t, opened)
    testing.expect(t, dialogue.available_count(&iva_conversation) == 2)
    testing.expect(
        t,
        dialogue.available_at(&iva_conversation, 0).text == "I'll carry your regatta acceptance to Niko.",
    )
    testing.expect(t, dialogue.available_at(&iva_conversation, 1).text == "I'll leave you to tend the lamp.")
}

@(test)
resident_action_indicators_follow_campaign_progress :: proc(t: ^testing.T) {
    state: story.State
    testing.expect(t, story.resident_name(.Gerta) == "Gerta")
    testing.expect(t, story.resident_name(.Vesna) == "Dr Vesna")
    testing.expect(t, story.resident_name(.Petar) == "Petar")
    testing.expect(t, story.resident_name(.Anica) == "Anica")
    testing.expect(t, story.resident_island(.Vesna) == .West)
    testing.expect(t, story.resident_island(.Petar) == .West)
    testing.expect(t, story.resident_island(.Anica) == .East)
    testing.expect(t, story.resident_island(.Gerta) == .West)
    testing.expect(t, story.resident_has_action(&state, .Marta))
    testing.expect(t, !story.resident_has_action(&state, .Gerta))
    testing.expect(t, !story.resident_has_action(&state, .Niko))
    testing.expect(t, !story.resident_has_action(&state, .Bojan))
    testing.expect(t, !story.resident_has_action(&state, .Iva))
    testing.expect(t, story.resident_has_unseen_action(&state, .Marta))
    story.acknowledge_resident_action(&state, .Marta)
    testing.expect(t, story.resident_has_action(&state, .Marta))
    testing.expect(t, !story.resident_has_unseen_action(&state, .Marta))

    testing.expect(t, story.accept_airfield_errand(&state))
    testing.expect(t, !story.resident_has_action(&state, .Marta))
    testing.expect(t, story.resident_has_action(&state, .Gerta))
    testing.expect(t, story.resident_has_unseen_action(&state, .Gerta))
    story.acknowledge_resident_action(&state, .Gerta)
    testing.expect(t, !story.resident_has_unseen_action(&state, .Gerta))
    testing.expect(t, story.handoff_broken_magneto(&state))
    testing.expect(t, story.resident_has_action(&state, .Marta))
    testing.expect(t, story.resident_has_unseen_action(&state, .Marta))
    testing.expect(t, !story.resident_has_action(&state, .Gerta))
    testing.expect(t, story.resident_has_action(&state, .Niko))
    testing.expect(t, story.resident_has_action(&state, .Bojan))
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, !story.resident_has_action(&state, .Niko))
    testing.expect(t, story.resident_has_action(&state, .Iva))
    complete_current_delivery(t, &state, .Iva)
    testing.expect(t, story.resident_has_action(&state, .Iva))

    repair_aircraft(t, &state)
    testing.expect(t, !story.resident_has_action(&state, .Bojan))

    state.romance = .Meeting
    state.delivery.active = false
    testing.expect(t, story.resident_has_action(&state, .Niko))
    testing.expect(t, !story.resident_has_action(&state, .Iva))
    testing.expect(t, !story.begin_delivery(&state))

    testing.expect(t, story.complete_meeting(&state))
    testing.expect(t, story.resident_has_action(&state, .Niko))
    testing.expect(t, !story.resident_has_action(&state, .Iva))
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, story.resident_has_action(&state, .Lena))
}

@(test)
two_island_quest_graph_projects_to_legacy_story_stages :: proc(t: ^testing.T) {
    catalog: story.Quest_Catalog
    story.init_quest_catalog(&catalog)
    testing.expect(t, quest.validate(&catalog.definition))

    graph_state: quest.State
    _, initialized := quest.init(&graph_state, &catalog.definition)
    testing.expect(t, initialized)

    legacy: story.State
    testing.expect(t, story.apply_quest_projection(&legacy, &graph_state, &catalog))
    testing.expect(t, legacy.romance == .Unintroduced)
    testing.expect(t, legacy.repair == .Not_Seen)
    testing.expect(t, legacy.airfield_errand == .Not_Offered)
    testing.expect(t, !quest.is_presented(&graph_state, &catalog.definition, story.quest_node_id(.Magneto_Westbound)))

    testing.expect(t, quest.accept(&graph_state, &catalog.definition, story.quest_node_id(.Magneto_Westbound)))
    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Deliver, key = "broken-magneto", target = "gerta"})
    testing.expect(t, quest.accept(&graph_state, &catalog.definition, story.quest_node_id(.Crash_Reported)))
    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Talk, key = "crash-reported", target = "bojan"})
    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Inspect, key = "bojan-wing"})
    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Repair, key = "apply-wing-patch"})
    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Repair, key = "verify-wing-repair"})
    testing.expect(t, story.apply_quest_projection(&legacy, &graph_state, &catalog))
    testing.expect(t, legacy.repair == .Repaired)
    testing.expect(t, legacy.romance == .Unintroduced)

    testing.expect(t, quest.accept(&graph_state, &catalog.definition, story.quest_node_id(.First_Letter)))
    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Deliver, key = "first-letter", target = "iva"})
    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Deliver, key = "first-reply", target = "niko"})
    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Deliver, key = "regatta-invitation", target = "iva"})
    testing.expect(t, story.apply_quest_projection(&legacy, &graph_state, &catalog))
    testing.expect(t, legacy.romance == .Invitation)
    testing.expect(
        t,
        quest.status(&graph_state, &catalog.definition, story.quest_node_id(.Regatta_Acceptance)) == .Active,
    )

    _ = quest.publish(
        &graph_state,
        &catalog.definition,
        {kind = .Deliver, key = "regatta-acceptance", target = "niko"},
    )
    testing.expect(t, story.apply_quest_projection(&legacy, &graph_state, &catalog))
    testing.expect(t, legacy.romance == .Meeting)
    testing.expect(t, legacy.stamps_earned == 4)

    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Talk, key = "awning-meeting"})
    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Deliver, key = "post-route"})
    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Deliver, key = "post-route"})
    testing.expect(t, story.apply_quest_projection(&legacy, &graph_state, &catalog))
    testing.expect(t, legacy.romance == .Together)
    testing.expect(t, legacy.repeat_deliveries == 2)
    testing.expect(t, legacy.completed_deliveries == 6)
    testing.expect(t, legacy.stamps_earned == 6)
}

@(test)
legacy_story_actions_publish_into_authoritative_quest_state :: proc(t: ^testing.T) {
    state: story.State
    catalog: story.Quest_Catalog
    story.init_quest_catalog(&catalog)

    testing.expect(t, story.accept_airfield_errand(&state))
    testing.expect(t, story.handoff_broken_magneto(&state))
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, story.complete_delivery(&state, .Iva))
    testing.expect(t, quest.is_complete(&state.quest, &catalog.definition, story.quest_node_id(.First_Letter)))
    testing.expect(t, state.romance == .First_Letter)
    testing.expect(t, state.stamps_earned == 1)

    testing.expect(t, story.report_crash(&state))
    testing.expect(t, story.diagnose_crash(&state))
    testing.expect(t, story.apply_wing_patch(&state))
    testing.expect(t, story.verify_repair(&state))
    testing.expect(t, quest.is_complete(&state.quest, &catalog.definition, story.quest_node_id(.Repair_Verified)))
    testing.expect(t, state.repair == .Repaired)
}

@(test)
westbound_opening_is_quiet_and_carries_main_and_side_cargo_together :: proc(t: ^testing.T) {
    state: story.State
    catalog: story.Quest_Catalog
    story.init_quest_catalog(&catalog)

    testing.expect(t, story.ensure_quest_progress(&state))
    testing.expect(t, state.airfield_errand == .Not_Offered)
    testing.expect(t, !state.delivery.active)
    testing.expect(t, quest.first_active(&state.quest, &catalog.definition) == story.quest_node_id(.Post_Route))
    testing.expect(t, !quest.is_presented(&state.quest, &catalog.definition, story.quest_node_id(.Magneto_Westbound)))
    testing.expect(t, !story.begin_delivery(&state))
    testing.expect(t, !story.report_crash(&state))

    testing.expect(t, story.accept_airfield_errand(&state))
    testing.expect(t, state.airfield_errand == .Westbound)
    testing.expect(t, quest.first_active(&state.quest, &catalog.definition) == story.quest_node_id(.Post_Route))
    testing.expect(t, quest.is_presented(&state.quest, &catalog.definition, story.quest_node_id(.Magneto_Westbound)))
    testing.expect(t, story.handoff_broken_magneto(&state))
    testing.expect(t, state.airfield_errand == .Eastbound)

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.active && state.delivery.kind == .First_Letter)
    testing.expect(t, story.return_replacement_magneto(&state))
    testing.expect(t, state.airfield_errand == .Completed)
    testing.expect(t, state.delivery.active && state.delivery.kind == .First_Letter)
    testing.expect(t, state.stamps_earned == 1)

    testing.expect(t, story.complete_delivery(&state, .Iva))
    testing.expect(t, state.romance == .First_Letter)
    testing.expect(t, state.stamps_earned == 2)
}

@(test)
legacy_progress_migrates_past_the_new_airfield_introduction :: proc(t: ^testing.T) {
    state := story.State {
        romance = .First_Letter,
        quest = {definition_id = "two-island-story", node_count = 11},
    }
    catalog: story.Quest_Catalog
    story.init_quest_catalog(&catalog)

    testing.expect(t, story.ensure_quest_progress(&state))
    testing.expect(t, state.quest.node_count == len(catalog.definition.nodes))
    testing.expect(t, state.airfield_errand == .Completed)
    testing.expect(t, state.romance == .First_Letter)
    testing.expect(t, quest.is_complete(&state.quest, &catalog.definition, story.quest_node_id(.Magneto_Eastbound)))
    testing.expect(t, state.stamps_earned == 2)
}
