package tests

import dialogue "../packages/dialogue"
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

@(test)
two_island_story_advances_on_completion_and_becomes_repeatable :: proc(t: ^testing.T) {
    state: story.State

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
    testing.expect(t, state.stamps_earned == 4)

    testing.expect(t, story.complete_meeting(&state))
    testing.expect(t, state.romance == .Together)

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.kind == .Repeat_Eastbound)
    testing.expect(t, state.delivery.subject == "Bread, postcards, and one pressed flower")
    complete_current_delivery(t, &state, .Iva)
    testing.expect(t, state.repeat_deliveries == 1 && state.stamps_earned == 5)

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.kind == .Repeat_Westbound)
    testing.expect(t, state.delivery.subject == "Lamp glass and a note for supper")
    complete_current_delivery(t, &state, .Niko)
    testing.expect(t, state.repeat_deliveries == 2 && state.stamps_earned == 6)
}

@(test)
early_repair_is_preserved_as_preparedness :: proc(t: ^testing.T) {
    state: story.State
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
        story.niko_text(&ctx) ==
        "La lampe de l'isola est clignote twice avant alba. Iva veglia quando mes forni aussi.",
    )
    testing.expect(
        t,
        story.bojan_text(&ctx) ==
        "L'atterraggio war perfekt. Le ground est arrivé trop tôt. Hai visto niente plus compliqué.",
    )

    state.romance = .Invitation
    testing.expect(
        t,
        story.iva_text(&ctx) == "Posso répondre à Niko, but l'ala rotta non peut me porter. Nema regatta todavía.",
    )
    repair_aircraft(t, &state)
    testing.expect(
        t,
        story.iva_text(&ctx) ==
        "Tu reparaste l'aereo de Bojan before che io lo necesitara. Grazie; jetzt posso rispondere.",
    )
    testing.expect(
        t,
        story.bojan_text(&ctx) == "L'aereo ist pronto pour Iva. Ho même nettoyé el asiento qui non m'appartient.",
    )

    iva_conversation, opened := dialogue.open(
        &catalog.iva,
        {data = rawptr(&state), location_id = "east_island", resident_index = int(story.Resident.Iva)},
    )
    testing.expect(t, opened)
    testing.expect(t, dialogue.available_count(&iva_conversation) == 2)
    testing.expect(t, dialogue.available_at(&iva_conversation, 0).text == "I'll porter ta risposta.")
    testing.expect(t, dialogue.available_at(&iva_conversation, 1).text == "Ti lascio tend the lampe.")
}

@(test)
resident_action_indicators_follow_campaign_progress :: proc(t: ^testing.T) {
    state: story.State
    testing.expect(t, story.resident_name(.Gerta) == "Gerta")
    testing.expect(t, story.resident_island(.Gerta) == .West)
    testing.expect(t, story.resident_has_action(&state, .Marta))
    testing.expect(t, story.resident_has_action(&state, .Gerta))
    testing.expect(t, story.resident_has_action(&state, .Niko))
    testing.expect(t, story.resident_has_action(&state, .Bojan))
    testing.expect(t, !story.resident_has_action(&state, .Iva))

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
    testing.expect(t, story.resident_has_action(&state, .Iva))
}
