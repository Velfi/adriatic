package tests

import dialogue "../packages/dialogue"
import quest "../packages/quest"
import story "../packages/story"
import tarot "../packages/tarot"
import "core:strings"
import "core:testing"

repair_aircraft :: proc(t: ^testing.T, state: ^story.State) {
    if !story.has_friendometer(state) do receive_friendometer(t, state)
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
    if !story.has_friendometer(state) do receive_friendometer(t, state)
    testing.expect(t, story.accept_airfield_errand(state))
    testing.expect(t, story.handoff_broken_magneto(state))
    testing.expect(t, story.return_replacement_magneto(state))
}

receive_friendometer :: proc(t: ^testing.T, state: ^story.State) {
    testing.expect(t, story.ensure_quest_progress(state))
    if story.has_friendometer(state) do return
    update, published := story.publish_quest_event(state, {kind = .Talk, key = "friendometer", target = "mirna"})
    testing.expect(t, published && update.completed_count == 1)
    testing.expect(t, story.has_friendometer(state))
}

expect_choice_texts :: proc(t: ^testing.T, actual: []dialogue.Choice, expected: []string) {
    testing.expect(t, len(actual) == len(expected))
    for choice, index in actual {
        testing.expect(t, choice.text == expected[index])
    }
}

@(test)
story_choices_fit_the_dialogue_buttons :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    definitions := [?]^dialogue.Definition {
        &catalog.niko,
        &catalog.iva,
        &catalog.bojan,
        &catalog.zora,
        &catalog.vesna,
        &catalog.petar,
        &catalog.anica,
        &catalog.toma,
        &catalog.lena,
        &catalog.mirna,
    }
    // Visual captures established forty ASCII bytes as the safe single-line
    // ceiling at the reference dialogue layout.
    for definition in definitions {
        for node in definition.nodes {
            for choice in node.choices {
                testing.expect(t, len(choice.text) <= 40)
            }
        }
    }
}

@(test)
speaker_labels_resolve_to_the_active_resident :: proc(t: ^testing.T) {
    labels := [?]string {
        "MARTA",
        "GERTA",
        "NIKO",
        "IVA",
        "BOJAN",
        "ZORA",
        "DR VESNA",
        "PETAR",
        "ANICA",
        "TOMA · POSTMASTER",
        "LENA · POSTMASTER",
        "DR MIRNA",
    }
    expected := [?]story.Resident {
        .Marta,
        .Gerta,
        .Niko,
        .Iva,
        .Bojan,
        .Zora,
        .Vesna,
        .Petar,
        .Anica,
        .Toma,
        .Lena,
        .Mirna,
    }
    for label, index in labels {
        resident, found := story.resident_from_speaker(label)
        testing.expect(t, found && resident == expected[index])
    }
    _, found_unknown := story.resident_from_speaker("UNKNOWN")
    testing.expect(t, !found_unknown)
}

@(test)
friendometer_is_the_only_opening_quest_and_unlocks_the_islands :: proc(t: ^testing.T) {
    state: story.State
    testing.expect(t, story.ensure_quest_progress(&state))
    catalog: story.Quest_Catalog
    story.init_quest_catalog(&catalog)

    testing.expect(t, quest.status(&state.quest, &catalog.definition, story.quest_node_id(.Friendometer)) == .Active)
    testing.expect(
        t,
        quest.status(&state.quest, &catalog.definition, story.quest_node_id(.Magneto_Westbound)) == .Locked,
    )
    testing.expect(t, quest.status(&state.quest, &catalog.definition, story.quest_node_id(.Post_Route)) == .Locked)

    dialogue_catalog: story.Catalog
    story.init_catalog(&dialogue_catalog)
    conversation, opened := dialogue.open(
        &dialogue_catalog.mirna,
        {data = rawptr(&state), location_id = "east_island", resident_index = int(story.Resident.Mirna)},
    )
    testing.expect(t, opened)
    testing.expect(
        t,
        dialogue.available_at(&conversation, 0).text == "What do my pockets have to do with science?",
    )
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, story.has_friendometer(&state))
    testing.expect(
        t,
        quest.status(&state.quest, &catalog.definition, story.quest_node_id(.Magneto_Westbound)) == .Available,
    )
    testing.expect(t, quest.status(&state.quest, &catalog.definition, story.quest_node_id(.Post_Route)) == .Active)
}

@(test)
friendship_points_only_accept_positive_rewards :: proc(t: ^testing.T) {
    state: story.State
    testing.expect(t, story.award_friendship(&state, 3))
    testing.expect(t, state.friendship_points == 3)
    testing.expect(t, !story.award_friendship(&state, 0))
    testing.expect(t, !story.award_friendship(&state, -1))
    testing.expect(t, state.friendship_points == 3)

    state.friendship_points = max(int)
    testing.expect(t, !story.award_friendship(&state, 1))
    testing.expect(t, state.friendship_points == max(int))
    testing.expect(t, !story.award_friendship(nil, 1))
}

@(test)
island_post_is_always_available_and_alternates_between_islands :: proc(t: ^testing.T) {
    state: story.State
    receive_friendometer(t, &state)

    testing.expect(t, story.begin_post_delivery(&state))
    testing.expect(t, state.romance == .Unintroduced)
    testing.expect(t, state.delivery.kind == .Repeat_Eastbound)
    testing.expect(t, state.delivery.origin == .West && state.delivery.destination == .East)
    complete_current_delivery(t, &state, .Lena)
    testing.expect(t, state.repeat_deliveries == 1 && state.stamps_earned == 1 && state.friendship_points == 1)

    testing.expect(t, story.begin_post_delivery(&state))
    testing.expect(t, state.delivery.kind == .Repeat_Westbound)
    testing.expect(t, state.delivery.origin == .East && state.delivery.destination == .West)
    complete_current_delivery(t, &state, .Toma)
    testing.expect(t, state.repeat_deliveries == 2 && state.stamps_earned == 2 && state.friendship_points == 2)

    // The independent postal route does not consume or advance the authored
    // correspondence storyline.
    complete_airfield_intro(t, &state)
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.kind == .First_Letter)
}

@(test)
careful_post_crossings_earn_merit_stamps :: proc(t: ^testing.T) {
    state: story.State
    receive_friendometer(t, &state)

    for crossing in 0 ..< 3 {
        testing.expect(t, story.begin_post_delivery(&state))
        testing.expect(t, story.choose_cargo_care(&state, .Orderly))
        recipient := crossing % 2 == 0 ? story.Resident.Lena : story.Resident.Toma
        testing.expect(t, story.complete_delivery(&state, recipient))
    }

    testing.expect(t, state.careful_deliveries == 3)
    testing.expect(t, state.bonus_stamps == 1)
    testing.expect(t, state.stamps_earned == 4)
}

@(test)
expressive_post_crossings_change_history_without_merit_bonus :: proc(t: ^testing.T) {
    state: story.State
    receive_friendometer(t, &state)

    testing.expect(t, story.begin_post_delivery(&state))
    testing.expect(t, story.choose_cargo_care(&state, .Expressive))
    testing.expect(t, story.complete_delivery(&state, .Lena))

    testing.expect(t, state.expressive_deliveries == 1)
    testing.expect(t, state.careful_deliveries == 0)
    testing.expect(t, state.bonus_stamps == 0)
    testing.expect(t, state.stamps_earned == 1)
}

@(test)
quest_ledger_uses_characterful_titles_with_clear_instructions :: proc(t: ^testing.T) {
    catalog: story.Quest_Catalog
    story.init_quest_catalog(&catalog)

    magneto := quest.find_node(&catalog.definition, story.quest_node_id(.Magneto_Westbound))
    wing := quest.find_node(&catalog.definition, story.quest_node_id(.Wing_Diagnosed))
    letter := quest.find_node(&catalog.definition, story.quest_node_id(.First_Letter))
    testing.expect(t, magneto != nil && magneto.title == "A Spark Across the Water")
    testing.expect(t, wing != nil && wing.title == "Canvas and Crosswind")
    testing.expect(t, letter != nil && letter.title == "A Recipe for a Clear Morning")
    testing.expect(t, magneto != nil && magneto.objective.key == "broken-magneto")
    testing.expect(t, wing != nil && wing.objective.key == "bojan-wing")
    testing.expect(t, letter != nil && letter.objective.key == "first-letter")
}

@(test)
island_post_departures_include_cycle_aware_handoffs :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state: story.State
    receive_friendometer(t, &state)
    ctx := dialogue.Context {
        data = rawptr(&state),
    }

    toma, toma_opened := dialogue.open(&catalog.toma, ctx)
    testing.expect(t, toma_opened)
    testing.expect(t, dialogue.choose(&toma, 0))
    testing.expect(t, state.delivery.active && state.delivery.kind == .Repeat_Eastbound)
    testing.expect(t, dialogue.current(&toma).id == "toma-handoff")
    testing.expect(t, dialogue.choose(&toma, 1))
    testing.expect(t, dialogue.current(&toma).id == "toma-handoff-improvise")
    testing.expect(t, state.delivery.active && state.delivery.kind == .Repeat_Eastbound)
    testing.expect(t, dialogue.choose(&toma, 0))
    testing.expect(t, toma.ended)

    testing.expect(t, story.complete_delivery(&state, .Lena))
    lena, lena_opened := dialogue.open(&catalog.lena, ctx)
    testing.expect(t, lena_opened)
    testing.expect(t, dialogue.choose(&lena, 0))
    testing.expect(t, state.delivery.active && state.delivery.kind == .Repeat_Westbound)
    testing.expect(t, dialogue.current(&lena).id == "lena-handoff")
    testing.expect(t, dialogue.choose(&lena, 0))
    testing.expect(t, dialogue.current(&lena).id == "lena-handoff-orderly")
    testing.expect(t, state.delivery.active && state.delivery.kind == .Repeat_Westbound)
    testing.expect(t, dialogue.choose(&lena, 0))
    testing.expect(t, lena.ended)
}

@(test)
island_post_arrivals_have_cycle_aware_player_shaped_payoffs :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state: story.State
    receive_friendometer(t, &state)
    ctx := dialogue.Context {
        data = rawptr(&state),
    }

    testing.expect(t, story.begin_post_delivery(&state))
    lena, lena_opened := dialogue.open(&catalog.lena, ctx)
    testing.expect(t, lena_opened)
    testing.expect(t, dialogue.choose(&lena, 0))
    testing.expect(t, state.repeat_deliveries == 1 && !state.delivery.active)
    testing.expect(t, dialogue.current(&lena).id == "lena-receipt")
    testing.expect(
        t,
        dialogue.current(&lena).text(&lena.ctx) ==
        "Pane ancora morbido, postcards piatte, fiore pressato intact. Toma l'ha messo in una customs declaration; apparentemente la tendresse demande paperwork.",
    )
    testing.expect(t, dialogue.choose(&lena, 1))
    testing.expect(t, dialogue.current(&lena).id == "lena-teasing")
    testing.expect(t, dialogue.choose(&lena, 0))
    testing.expect(t, lena.ended)

    testing.expect(t, story.begin_post_delivery(&state))
    toma, toma_opened := dialogue.open(&catalog.toma, ctx)
    testing.expect(t, toma_opened)
    testing.expect(t, dialogue.choose(&toma, 0))
    testing.expect(t, state.repeat_deliveries == 2 && !state.delivery.active)
    testing.expect(t, dialogue.current(&toma).id == "toma-receipt")
    testing.expect(
        t,
        dialogue.current(&toma).text(&toma.ctx) ==
        "Lamp glass intera, dinner note leggibile, pane saggiamente separato. Lena ha sottolineato SUPPER due volte; non è plus correspondance, è navigation.",
    )
    testing.expect(t, dialogue.choose(&toma, 0))
    testing.expect(t, dialogue.current(&toma).id == "toma-orderly")
    testing.expect(t, dialogue.choose(&toma, 0))
    testing.expect(t, toma.ended)
}

@(test)
postmaster_receipt_attitudes_remember_each_cargo_cycle :: proc(t: ^testing.T) {
    toma_counts := [3]int{2, 4, 6}
    toma_orderly := [3]string {
        "Ho observé. Angoli asciutti, stack dritta, niente crushed. Un postmaster nota la cura anche quand il ledger non ha colonna.",
        "Ho observé. Weather reports piatti, lamp glass intera, und zero correction in blue pencil en route. Excellent restraint.",
        "Ho observé. Glass sotto, note sopra, zero basilico non autorizzato. Même l'accusa del watering can è arrivée dritta.",
    }
    toma_teasing := [3]string {
        "Officiellement, la lamp glass aveva priorità. Non ufficialmente, ho letto SUPPER avant la crack. Non revisionare il ledger.",
        "Lena ha ritornato ogni forecast con evidence. Ho inspectato la blue pencil prima—curiosità professionale, naturellement.",
        "Il watering can era très chiaro. La lamp glass ha solo confirmato che il parcel è sopravvissuto; la mia réputation, non.",
    }
    lena_counts := [3]int{1, 3, 5}
    lena_orderly := [3]string {
        "Ho observé. Carta asciutta, pane morbido, ogni angolo rispettato. La cura è il postal mark che nessuno può contraffare.",
        "Ho observé. Blue pencil asciutta, pane morbido, postcards quadrate. Même i bite marks di Toma sono arrivati dove registrati.",
        "Ho observé. Basilico verticale, radici umide, customs form assurdamente piatto. La cura può survivre alla burocrazia.",
    }
    lena_teasing := [3]string {
        "Naturalmente. Toma supervise con due mani, puis scrive un form dicendo che il parcel si è arrangiato. Archivierò la testimonianza.",
        "Personalmente, sì. Ha protetto la pencil comme gioielli reali, puis negato ogni bite mark in triplicato.",
        "Toma ha supervisé il basilico finché ha acquisito paperwork. Io irrigo la plant et archivio la sua ansia.",
    }
    for index in 0 ..< 3 {
        toma_state := story.State {
            repeat_deliveries = toma_counts[index],
        }
        toma_ctx := dialogue.Context {
            data = rawptr(&toma_state),
        }
        testing.expect(t, story.toma_post_orderly_close(&toma_ctx) == toma_orderly[index])
        testing.expect(t, story.toma_post_teasing_close(&toma_ctx) == toma_teasing[index])

        lena_state := story.State {
            repeat_deliveries = lena_counts[index],
        }
        lena_ctx := dialogue.Context {
            data = rawptr(&lena_state),
        }
        testing.expect(t, story.lena_post_orderly_close(&lena_ctx) == lena_orderly[index])
        testing.expect(t, story.lena_post_teasing_close(&lena_ctx) == lena_teasing[index])
    }
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
    receive_friendometer(t, &state)
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
            "Give Niko Iva's package.",
            "I'll carry your sealed letter to Iva.",
            "I'll take Iva the regatta invitation.",
            "I'll carry the next package to Iva.",
            "Stay under the awning.",
            "How are things beneath the blue awning?",
            "I'll leave you to your work.",
        },
    )
    expect_choice_texts(
        t,
        catalog.niko_reaction_choices[:],
        []string{"You look pleased.", "The letter stayed sealed."},
    )
    expect_choice_texts(t, catalog.niko_warm_choices[:], []string{"Safe crossing, Niko."})
    expect_choice_texts(t, catalog.niko_discreet_choices[:], []string{"Not a word from me."})
    expect_choice_texts(
        t,
        catalog.niko_handoff_choices[:],
        []string{"I'll keep it dry and in order.", "I'll ignore any personal evidence."},
    )
    expect_choice_texts(t, catalog.niko_handoff_close_choices[:], []string{"East island, then."})
    expect_choice_texts(
        t,
        catalog.niko_together_choices[:],
        []string{"You found a good rhythm.", "I'll call the experiment successful."},
    )
    expect_choice_texts(t, catalog.niko_together_close_choices[:], []string{"I'll leave the scheduling to you."})
    expect_choice_texts(
        t,
        catalog.meeting_choices[:],
        []string{"The awning suits you both.", "I saw only an ordinary arrival."},
    )
    expect_choice_texts(t, catalog.meeting_warm_choices[:], []string{"And enough bread for a delayed plane."})
    expect_choice_texts(t, catalog.meeting_discreet_choices[:], []string{"I can forget the landing, not the bread."})
    expect_choice_texts(t, catalog.meeting_finish_choices[:], []string{"Enjoy the regatta."})
    expect_choice_texts(
        t,
        catalog.iva_root_choices[:],
        []string {
            "Give Iva Niko's sealed letter.",
            "Give Iva Niko's regatta invitation.",
            "Give Iva Niko's package.",
            "I'll carry your reply to Niko.",
            "I'll take Niko the regatta acceptance.",
            "I'll carry the next package to Niko.",
            "How is the west island treating you?",
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
        catalog.iva_handoff_choices[:],
        []string{"I'll keep everything dry and intact.", "I'll follow your packing instructions."},
    )
    expect_choice_texts(t, catalog.iva_handoff_close_choices[:], []string{"West island, then."})
    expect_choice_texts(
        t,
        catalog.iva_together_choices[:],
        []string{"The system seems to suit you both.", "I'll trust your evidence."},
    )
    expect_choice_texts(t, catalog.iva_together_close_choices[:], []string{"I'll leave you to the next crossing."})
    expect_choice_texts(
        t,
        catalog.bojan_choices[:],
        []string {
            "I saw the whole thing.",
            "Let's inspect the wing.",
            "Apply the canvas patch.",
            "Turn the propeller.",
            "How is our canvas patch holding?",
            "I'll leave you to it.",
        },
    )
    expect_choice_texts(t, catalog.bojan_report_choices[:], []string{"Show me where the canvas tore."})
    expect_choice_texts(
        t,
        catalog.bojan_inspect_choices[:],
        []string{"The rib is sound; only the canvas tore.", "The ground signed its name here."},
    )
    expect_choice_texts(t, catalog.bojan_inspect_close_choices[:], []string{"Let's fit the canvas patch."})
    expect_choice_texts(t, catalog.bojan_patch_choices[:], []string{"Let's test the controls."})
    expect_choice_texts(
        t,
        catalog.bojan_repair_choices[:],
        []string{"The controls move cleanly.", "All three wheels survived."},
    )
    expect_choice_texts(t, catalog.bojan_repair_close_choices[:], []string{"Then the aeroplano is ready."})
    expect_choice_texts(
        t,
        catalog.bojan_check_choices[:],
        []string{"Show me the inspection marks.", "The patch outperforms its pilot."},
    )
    expect_choice_texts(t, catalog.bojan_check_close_choices[:], []string{"Keep it out of the ground."})
    expect_choice_texts(
        t,
        catalog.zora_choices[:],
        []string {
            "Which way is the wind blowing?",
            "Past, present, and possible shore.",
            "I have time. Lay out the full cross.",
            "Remind me what I should watch for.",
            "Another time, grazie.",
            "Get an airfield weather reading.",
        },
    )
    expect_choice_texts(
        t,
        catalog.zora_reading_choices[:],
        []string{"What should I watch for?", "Enough cards. I'll watch the real sky."},
    )
    expect_choice_texts(t, catalog.zora_counsel_choices[:], []string{"Then I'll choose the next crossing."})
    expect_choice_texts(
        t,
        catalog.zora_recall_choices[:],
        []string{"I'll act before asking the cards again.", "I'll trust the sky more than the cards."},
    )
    expect_choice_texts(t, catalog.zora_recall_close_choices[:], []string{"Then I'll get moving."})
    expect_choice_texts(
        t,
        catalog.vesna_choices[:],
        []string {
            "Thanks, doctor. I'll take it slower.",
            "The landing looked softer from above.",
            "I checked the weather. It wasn't enough.",
            "I remembered where my glasses go.",
            "Carry the clinic medicine east.",
            "Give Vesna the sealed water.",
        },
    )
    expect_choice_texts(t, catalog.vesna_close_choices[:], []string{"I'll check the weather first."})
    expect_choice_texts(
        t,
        catalog.petar_choices[:],
        []string {
            "I'll use the door next time.",
            "The window was closer.",
            "The door was not involved this time.",
            "Do the linens recognize me now?",
            "Carry the dry clinic linens east.",
        },
    )
    expect_choice_texts(t, catalog.petar_close_choices[:], []string{"I'll keep the linens out of it."})
    expect_choice_texts(
        t,
        catalog.anica_choices[:],
        []string {
            "Water first. Understood.",
            "I thought the sea was keeping count.",
            "Water first. I remembered.",
            "Should I reserve this bed by name?",
            "Give Anica the clinic medicine.",
            "Give Anica the dry clinic linens.",
            "Carry the sealed water west.",
        },
    )
    expect_choice_texts(t, catalog.anica_close_choices[:], []string{"I'll make the next appointment quieter."})
    expect_choice_texts(
        t,
        catalog.toma_handoff_choices[:],
        []string{"I'll follow the ledger exactly.", "I'll improvise if the sea does."},
    )
    expect_choice_texts(t, catalog.toma_handoff_close_choices[:], []string{"Eastbound, then."})
    expect_choice_texts(
        t,
        catalog.toma_receipt_choices[:],
        []string{"Everything stayed in its proper place.", "The supper note outranked the glass."},
    )
    expect_choice_texts(t, catalog.toma_close_choices[:], []string{"Your ledger is safe with me."})
    expect_choice_texts(
        t,
        catalog.lena_handoff_choices[:],
        []string{"I'll keep Toma's post in order.", "I'll make sure he reads SUPPER first."},
    )
    expect_choice_texts(t, catalog.lena_handoff_close_choices[:], []string{"Westbound, then."})
    expect_choice_texts(
        t,
        catalog.lena_receipt_choices[:],
        []string{"Everything stayed dry and flat.", "Toma supervised every item personally."},
    )
    expect_choice_texts(t, catalog.lena_close_choices[:], []string{"I'll leave the filing to you."})

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
    testing.expect(t, dialogue.current(&conversation).id == "meeting-iva-warm")
    testing.expect(t, state.romance == .Meeting)
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, conversation.ended)
    testing.expect(t, state.romance == .Together)
}

@(test)
blue_awning_meeting_keeps_each_voice_distinct_on_both_paths :: proc(t: ^testing.T) {
    testing.expect(
        t,
        story.meeting_iva_text(nil) ==
        "La tenda blu è exactement dove Niko l'ha descritta. Bojan chiama il volo routine, mais un atterraggio routine usa tutte tre ruote, sì?",
    )
    testing.expect(
        t,
        story.meeting_niko_warm(nil) ==
        "La terza ruota era décorative. Siediti, per favore; ho fatto abbastanza pane pour una regatta und un aeroplano tardivo.",
    )
    testing.expect(
        t,
        story.meeting_iva_warm_close(nil) ==
        "Ha contato il pane due volte und les minutes tre. Sono arrivata avant che finisse uno dei due.",
    )
    testing.expect(
        t,
        story.meeting_niko_discreet(nil) ==
        "Alors non hai visto niente, grazie. Solo un baker, una custode du phare, und pranzo sotto una tenda ordinaria.",
    )
    testing.expect(
        t,
        story.meeting_iva_discreet_close(nil) ==
        "Una tenda très ordinaria. Niko ha lucidato la frame ieri—due volte, mit completa indifferenza.",
    )

    catalog: story.Catalog
    story.init_catalog(&catalog)
    state := story.State {
        romance = .Meeting,
        repair  = .Repaired,
    }
    conversation, opened := dialogue.open(
        &catalog.niko,
        {data = rawptr(&state), location_id = "west_island", resident_index = int(story.Resident.Niko)},
    )
    testing.expect(t, opened)
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, dialogue.current(&conversation).id == "meeting-iva")
    testing.expect(t, dialogue.choose(&conversation, 1))
    testing.expect(t, dialogue.current(&conversation).id == "meeting-niko-discreet")
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, dialogue.current(&conversation).id == "meeting-iva-discreet")
    testing.expect(t, state.romance == .Meeting)
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, state.romance == .Together)
}

@(test)
niko_and_iva_keep_talking_after_the_meeting :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state := story.State {
        romance           = .Together,
        repeat_deliveries = 2,
    }
    ctx := dialogue.Context {
        data = rawptr(&state),
    }

    niko, niko_opened := dialogue.open(&catalog.niko, ctx)
    testing.expect(t, niko_opened)
    testing.expect(t, dialogue.available_count(&niko) == 3)
    testing.expect(t, dialogue.choose(&niko, 1))
    testing.expect(t, dialogue.current(&niko).id == "niko-together")
    testing.expect(t, len(dialogue.current(&niko).text(&niko.ctx)) > 0)
    testing.expect(t, dialogue.choose(&niko, 1))
    testing.expect(t, dialogue.current(&niko).id == "niko-together-experiment")
    testing.expect(t, dialogue.choose(&niko, 0))
    testing.expect(t, niko.ended)

    iva, iva_opened := dialogue.open(&catalog.iva, ctx)
    testing.expect(t, iva_opened)
    testing.expect(t, dialogue.available_count(&iva) == 2)
    testing.expect(t, dialogue.choose(&iva, 0))
    testing.expect(t, dialogue.current(&iva).id == "iva-together")
    testing.expect(t, len(dialogue.current(&iva).text(&iva.ctx)) > 0)
    testing.expect(t, dialogue.choose(&iva, 0))
    testing.expect(t, dialogue.current(&iva).id == "iva-together-system")
    testing.expect(t, dialogue.choose(&iva, 0))
    testing.expect(t, iva.ended)
}

@(test)
correspondence_departures_include_a_letter_handoff :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state: story.State
    complete_airfield_intro(t, &state)

    niko, niko_opened := dialogue.open(
        &catalog.niko,
        {data = rawptr(&state), location_id = "west_island", resident_index = int(story.Resident.Niko)},
    )
    testing.expect(t, niko_opened)
    testing.expect(t, dialogue.choose(&niko, 0))
    testing.expect(t, state.delivery.active && state.delivery.kind == .First_Letter)
    testing.expect(t, dialogue.current(&niko).id == "niko-handoff")
    testing.expect(t, dialogue.choose(&niko, 1))
    testing.expect(t, dialogue.current(&niko).id == "niko-handoff-playful")
    testing.expect(t, state.delivery.active && state.delivery.kind == .First_Letter)
    testing.expect(t, dialogue.choose(&niko, 0))
    testing.expect(t, niko.ended)

    testing.expect(t, story.complete_delivery(&state, .Iva))
    iva, iva_opened := dialogue.open(
        &catalog.iva,
        {data = rawptr(&state), location_id = "east_island", resident_index = int(story.Resident.Iva)},
    )
    testing.expect(t, iva_opened)
    testing.expect(t, dialogue.choose(&iva, 0))
    testing.expect(t, state.delivery.active && state.delivery.kind == .First_Reply)
    testing.expect(t, dialogue.current(&iva).id == "iva-handoff")
    testing.expect(t, dialogue.choose(&iva, 0))
    testing.expect(t, dialogue.current(&iva).id == "iva-handoff-careful")
    testing.expect(t, state.delivery.active && state.delivery.kind == .First_Reply)
    testing.expect(t, dialogue.choose(&iva, 0))
    testing.expect(t, iva.ended)
}

@(test)
niko_and_iva_expose_truthful_alternating_package_handoffs_after_meeting :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state: story.State
    complete_airfield_intro(t, &state)

    testing.expect(t, story.begin_delivery(&state))
    complete_current_delivery(t, &state, .Iva)
    testing.expect(t, story.begin_delivery(&state))
    complete_current_delivery(t, &state, .Niko)
    testing.expect(t, story.begin_delivery(&state))
    complete_current_delivery(t, &state, .Iva)
    repair_aircraft(t, &state)
    testing.expect(t, story.begin_delivery(&state))
    complete_current_delivery(t, &state, .Niko)
    testing.expect(t, story.complete_meeting(&state))
    testing.expect(t, state.romance == .Together)

    niko, niko_opened := dialogue.open(
        &catalog.niko,
        {data = rawptr(&state), location_id = "west_island", resident_index = int(story.Resident.Niko)},
    )
    testing.expect(t, niko_opened)
    testing.expect(t, dialogue.available_count(&niko) == 3)
    testing.expect(t, dialogue.choose(&niko, 0))
    testing.expect(t, state.delivery.active && state.delivery.kind == .Repeat_Eastbound)
    testing.expect(t, dialogue.current(&niko).id == "niko-handoff")
    testing.expect(
        t,
        dialogue.current(&niko).text(&niko.ctx) ==
        "For Iva: warm pane, postcards, und one pressed flower. Keep la package above the spray; sentiment has poor waterproofing.",
    )
    testing.expect(t, dialogue.choose(&niko, 0))
    testing.expect(t, dialogue.current(&niko).id == "niko-handoff-careful")
    testing.expect(
        t,
        dialogue.current(&niko).text(&niko.ctx) ==
        "Grazie. Pane on top, postcards flat, flower sheltered. La package can survive il mare without becoming a story.",
    )
    testing.expect(t, dialogue.choose(&niko, 0))
    testing.expect(t, niko.ended)

    complete_current_delivery(t, &state, .Iva)
    iva, iva_opened := dialogue.open(
        &catalog.iva,
        {data = rawptr(&state), location_id = "east_island", resident_index = int(story.Resident.Iva)},
    )
    testing.expect(t, iva_opened)
    testing.expect(t, dialogue.available_count(&iva) == 3)
    testing.expect(t, dialogue.choose(&iva, 0))
    testing.expect(t, state.delivery.active && state.delivery.kind == .Repeat_Westbound)
    testing.expect(t, dialogue.current(&iva).id == "iva-handoff")
    testing.expect(
        t,
        dialogue.current(&iva).text(&iva.ctx) ==
        "For Niko: lamp glass below, dinner note above. Keep la package dry; only one item survives being read in rain.",
    )
    testing.expect(t, dialogue.choose(&iva, 1))
    testing.expect(t, dialogue.current(&iva).id == "iva-handoff-lights")
    testing.expect(
        t,
        dialogue.current(&iva).text(&iva.ctx) ==
        "Follow them exactly enough to blame me. La glass is fragile; il dinner note only pretends to be.",
    )
}

@(test)
clinic_residents_respond_to_the_players_tone :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state := story.State {
        clinic_visits = 1,
    }
    ctx := dialogue.Context {
        data        = rawptr(&state),
        location_id = "clinic",
    }

    vesna, vesna_opened := dialogue.open(&catalog.vesna, ctx)
    testing.expect(t, vesna_opened)
    testing.expect(t, dialogue.choose(&vesna, 1))
    testing.expect(t, dialogue.current(&vesna).id == "vesna-joke")
    testing.expect(t, dialogue.choose(&vesna, 0))
    testing.expect(t, vesna.ended)

    petar, petar_opened := dialogue.open(&catalog.petar, ctx)
    testing.expect(t, petar_opened)
    testing.expect(t, dialogue.choose(&petar, 0))
    testing.expect(t, dialogue.current(&petar).id == "petar-door")

    anica, anica_opened := dialogue.open(&catalog.anica, ctx)
    testing.expect(t, anica_opened)
    testing.expect(t, dialogue.choose(&anica, 1))
    testing.expect(t, dialogue.current(&anica).id == "anica-sea")
}

@(test)
clinic_residents_explain_a_fall_and_possible_concussion_dreams :: proc(t: ^testing.T) {
    state := story.State {
        clinic_visits                = 1,
        last_clinic_visit_was_tumble = true,
    }
    ctx := dialogue.Context {
        data        = rawptr(&state),
        location_id = "clinic",
    }

    testing.expect(t, strings.contains(story.vesna_text(&ctx), "ti ha visto"))
    testing.expect(t, strings.contains(story.vesna_text(&ctx), "concussion"))
    testing.expect(t, strings.contains(story.petar_text(&ctx), "sogni"))
    testing.expect(t, strings.contains(story.anica_text(&ctx), "tumble"))
}

@(test)
clinic_residents_change_the_conversation_on_repeat_visits :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state := story.State {
        clinic_visits = 3,
    }
    ctx := dialogue.Context {
        data        = rawptr(&state),
        location_id = "clinic",
    }

    vesna, vesna_opened := dialogue.open(&catalog.vesna, ctx)
    testing.expect(t, vesna_opened)
    testing.expect(t, dialogue.available_count(&vesna) == 2)
    testing.expect(t, dialogue.choose(&vesna, 0))
    testing.expect(t, dialogue.current(&vesna).id == "vesna-repeat-honest")

    petar, petar_opened := dialogue.open(&catalog.petar, ctx)
    testing.expect(t, petar_opened)
    testing.expect(t, dialogue.available_count(&petar) == 2)
    testing.expect(t, dialogue.choose(&petar, 1))
    testing.expect(t, dialogue.current(&petar).id == "petar-repeat-linens")

    anica, anica_opened := dialogue.open(&catalog.anica, ctx)
    testing.expect(t, anica_opened)
    testing.expect(t, dialogue.available_count(&anica) == 2)
    testing.expect(t, dialogue.choose(&anica, 1))
    testing.expect(t, dialogue.current(&anica).id == "anica-repeat-bed")
}

@(test)
clinic_trio_recognizes_repeat_visits_without_sharing_a_voice :: proc(t: ^testing.T) {
    states := [3]story.State{{clinic_visits = 2}, {clinic_visits = 3}, {clinic_visits = 4}}
    vesna_expected := [3]string {
        "Visita numero 2. Stesso pilota, nuova bruise, und occhiali familiari. Bene: acqua prima; puis compariamo la storia con il meteo.",
        "Visita numero 3. Conosci la routine: acqua, repos, puis inspecta il meteo avant il motor.",
        "Visita numero 4. Il tray ha ricordato gli occhiali; preferisco quando i pazienti imparano plus vite dei mobili. Acqua, repos, meteo.",
    }
    petar_expected := [3]string {
        "Visita numero 2. La scarf è asciutta, la door resta innocente, und l'aeroplano aspetta fuori. In questo ordine.",
        "Visita numero 3. Gli occhiali hanno trouvé il tray senza assistenza. Magari il pilota mostrasse uguale navigation.",
        "Visita numero 4. Una scarf asciutta, due sheets pulite, und zero applausi. Vesna gestisce medicine; io proteggo le linens.",
    }
    anica_expected := [3]string {
        "Encore, numero 2. Ho mosso l'acqua plus vicina et l'appointment book plus lontano. Una di noi sta imparando.",
        "Encore tu, visita numero 3. Il mare pardonne beaucoup, mais non conserva i miei records.",
        "Visita numero 4. Acqua aspetta al letto, meteo sul muro, und il mare non aspetta nessuno. Scegli la prima.",
    }
    for index in 0 ..< len(states) {
        ctx := dialogue.Context {
            data        = rawptr(&states[index]),
            location_id = "clinic",
        }
        testing.expect(t, story.vesna_text(&ctx) == vesna_expected[index])
        testing.expect(t, story.petar_text(&ctx) == petar_expected[index])
        testing.expect(t, story.anica_text(&ctx) == anica_expected[index])
    }
}

@(test)
bojan_repair_plays_as_one_collaborative_conversation :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state: story.State
    complete_airfield_intro(t, &state)

    conversation, opened := dialogue.open(
        &catalog.bojan,
        {data = rawptr(&state), location_id = "west_island", resident_index = int(story.Resident.Bojan)},
    )
    testing.expect(t, opened)

    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, state.repair == .Crash_Reported)
    testing.expect(t, dialogue.current(&conversation).id == "bojan-report")
    testing.expect(t, dialogue.choose(&conversation, 0))

    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, state.repair == .Diagnosed)
    testing.expect(t, dialogue.current(&conversation).id == "bojan-inspect")
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, dialogue.current(&conversation).id == "bojan-inspect-practical")
    testing.expect(
        t,
        dialogue.current(&conversation).text(&conversation.ctx) == story.bojan_inspect_practical_close(nil),
    )
    testing.expect(t, dialogue.choose(&conversation, 0))

    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, state.repair == .Patched)
    testing.expect(t, dialogue.current(&conversation).id == "bojan-patch")
    testing.expect(t, dialogue.choose(&conversation, 0))

    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, state.repair == .Repaired)
    testing.expect(t, dialogue.current(&conversation).id == "bojan-repaired")
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, dialogue.current(&conversation).id == "bojan-repair-controls")
    testing.expect(t, state.repair == .Repaired)
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, conversation.ended)
}

@(test)
bojan_answers_both_repair_payoff_attitudes_after_completion :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    for choice_index in 0 ..< len(catalog.bojan_repair_choices) {
        state: story.State
        complete_airfield_intro(t, &state)
        testing.expect(t, story.report_crash(&state))
        testing.expect(t, story.diagnose_crash(&state))
        testing.expect(t, story.apply_wing_patch(&state))
        testing.expect(t, state.repair == .Patched)
        conversation, opened := dialogue.open(
            &catalog.bojan,
            {data = rawptr(&state), location_id = "west_island", resident_index = int(story.Resident.Bojan)},
        )
        testing.expect(t, opened)
        testing.expect(t, dialogue.choose(&conversation, 0))
        testing.expect(t, state.repair == .Repaired)
        testing.expect(t, dialogue.current(&conversation).id == "bojan-repaired")
        testing.expect(t, dialogue.choose(&conversation, choice_index))
        expected_id := choice_index == 0 ? "bojan-repair-controls" : "bojan-repair-wheels"
        testing.expect(t, dialogue.current(&conversation).id == expected_id)
        testing.expect(t, state.repair == .Repaired)
        testing.expect(t, dialogue.choose(&conversation, 0))
        testing.expect(t, conversation.ended)
    }
}

@(test)
bojan_answers_both_inspection_attitudes_without_changing_the_repair :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    for choice_index in 0 ..< len(catalog.bojan_inspect_choices) {
        state := story.State {
            repair = .Crash_Reported,
        }
        conversation, opened := dialogue.open(
            &catalog.bojan,
            {data = rawptr(&state), location_id = "west_island", resident_index = int(story.Resident.Bojan)},
        )
        testing.expect(t, opened)
        testing.expect(t, dialogue.choose(&conversation, 0))
        testing.expect(t, state.repair == .Diagnosed)
        testing.expect(t, dialogue.choose(&conversation, choice_index))
        testing.expect(t, state.repair == .Diagnosed)
        expected_id := choice_index == 0 ? "bojan-inspect-practical" : "bojan-inspect-teasing"
        testing.expect(t, dialogue.current(&conversation).id == expected_id)
        testing.expect(t, dialogue.choose(&conversation, 0))
        testing.expect(t, dialogue.current(&conversation).id == "bojan")
        testing.expect(t, dialogue.available_count(&conversation) == 2)
    }
}

@(test)
bojan_remembers_the_repair_and_responds_to_the_players_tone :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state := story.State {
        repair            = .Repaired,
        romance           = .Together,
        repeat_deliveries = 2,
    }
    ctx := dialogue.Context {
        data           = rawptr(&state),
        location_id    = "west_island",
        resident_index = int(story.Resident.Bojan),
    }

    teasing, teasing_opened := dialogue.open(&catalog.bojan, ctx)
    testing.expect(t, teasing_opened)
    testing.expect(t, dialogue.choose(&teasing, 0))
    testing.expect(t, dialogue.current(&teasing).id == "bojan-check")
    testing.expect(
        t,
        dialogue.current(&teasing).text(&teasing.ctx) ==
        "Iva marks every flight in a little meteo book. Beside my last landing she wrote: 'adequate, eventually.' Très scientific.",
    )
    testing.expect(t, dialogue.choose(&teasing, 1))
    testing.expect(t, dialogue.current(&teasing).id == "bojan-check-teasing")
    testing.expect(t, dialogue.choose(&teasing, 0))
    testing.expect(t, teasing.ended)

    practical, practical_opened := dialogue.open(&catalog.bojan, ctx)
    testing.expect(t, practical_opened)
    testing.expect(t, dialogue.choose(&practical, 0))
    testing.expect(t, dialogue.choose(&practical, 0))
    testing.expect(t, dialogue.current(&practical).id == "bojan-check-practical")
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
    testing.expect(t, dialogue.current(&conversation).id == "zora-counsel")
    counsel := dialogue.current(&conversation).text(&conversation.ctx)
    testing.expect(t, len(counsel) > 0)
    testing.expect(t, dialogue.choose(&conversation, 0))
    testing.expect(t, conversation.ended)

    same_moment, reopened := dialogue.open(
        &catalog.zora,
        {data = rawptr(&state), location_id = "east_island", resident_index = int(story.Resident.Zora)},
    )
    testing.expect(t, reopened)
    testing.expect(t, dialogue.available_count(&same_moment) == 2)
    remembered_card := state.tarot_layout.placements[0]
    remembered_seed := state.tarot_seed
    remembered_count := state.tarot_readings
    remembered_moment := state.tarot_last_moment
    testing.expect(t, dialogue.choose(&same_moment, 0))
    testing.expect(t, dialogue.current(&same_moment).id == "zora-recall")
    testing.expect(t, len(dialogue.current(&same_moment).text(&same_moment.ctx)) > 0)
    testing.expect(t, state.tarot_readings == remembered_count)
    testing.expect(t, state.tarot_seed == remembered_seed)
    testing.expect(t, state.tarot_last_moment == remembered_moment)
    testing.expect(t, state.tarot_layout.placements[0] == remembered_card)
    testing.expect(t, dialogue.choose(&same_moment, 1))
    testing.expect(t, dialogue.current(&same_moment).id == "zora-recall-sky")
    testing.expect(t, dialogue.choose(&same_moment, 0))
    testing.expect(t, same_moment.ended)

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
        "La lampe dell'isola est clignote due volte avant alba. Iva veglia mentre les forni scaldano.",
    )
    testing.expect(
        t,
        story.bojan_text(&ctx) ==
        "L'atterraggio era perfekt. Le sol è arrivato troppo presto. Hai visto zero complication.",
    )
    testing.expect(
        t,
        story.zora_text(&ctx) ==
        "Ferme la persiana, piccolo corriere, que la bura mélange ya abbastanza. Die carte non commandano el mare; solamente indicano dónde der vento quiere girare.",
    )

    state.romance = .Invitation
    testing.expect(
        t,
        story.iva_text(&ctx) == "Io posso répondre a Niko, mais l'ala rotta non può portarmi. Nema regatta ancora.",
    )
    repair_aircraft(t, &state)
    testing.expect(
        t,
        story.iva_text(&ctx) ==
        "Tu hai réparé l'aeroplano di Bojan avant che servisse. Grazie; ora puoi portare la regatta acceptance.",
    )
    testing.expect(
        t,
        story.bojan_text(&ctx) == "L'aereo è pronto pour Iva. Ho même pulito il seat che non mi appartiene.",
    )

    iva_conversation, opened := dialogue.open(
        &catalog.iva,
        {data = rawptr(&state), location_id = "east_island", resident_index = int(story.Resident.Iva)},
    )
    testing.expect(t, opened)
    testing.expect(t, dialogue.available_count(&iva_conversation) == 2)
    testing.expect(t, dialogue.available_at(&iva_conversation, 0).text == "I'll take Niko the regatta acceptance.")
    testing.expect(t, dialogue.available_at(&iva_conversation, 1).text == "I'll leave you to tend the lamp.")
}

@(test)
resident_action_indicators_follow_campaign_progress :: proc(t: ^testing.T) {
    state: story.State
    receive_friendometer(t, &state)
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

    _ = quest.publish(&graph_state, &catalog.definition, {kind = .Talk, key = "friendometer", target = "mirna"})
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
resident_errands_require_real_inspection_and_cross_island_deliveries :: proc(t: ^testing.T) {
    state: story.State
    receive_friendometer(t, &state)
    catalog: story.Quest_Catalog
    story.init_quest_catalog(&catalog)

    testing.expect(t, story.accept_weather_reading(&state))
    testing.expect(t, !state.weather_reading_done)
    testing.expect(t, story.complete_weather_reading(&state))
    testing.expect(t, state.weather_reading_done)
    testing.expect(t, quest.is_complete(&state.quest, &catalog.definition, story.quest_node_id(.Weather_Reading)))

    testing.expect(t, story.begin_local_delivery(&state, .Clinic_Medicine))
    testing.expect(t, state.delivery.from == .Vesna && state.delivery.to == .Anica)
    testing.expect(t, story.complete_delivery(&state, .Anica))
    testing.expect(t, state.medicine_delivered)

    testing.expect(t, story.begin_local_delivery(&state, .Clinic_Linens))
    testing.expect(t, state.delivery.from == .Petar && state.delivery.to == .Anica)
    testing.expect(t, story.complete_delivery(&state, .Anica))
    testing.expect(t, state.linens_delivered)

    testing.expect(t, story.begin_local_delivery(&state, .Clinic_Water))
    testing.expect(t, state.delivery.from == .Anica && state.delivery.to == .Vesna)
    testing.expect(t, story.complete_delivery(&state, .Vesna))
    testing.expect(t, state.water_delivered)
    testing.expect(t, state.stamps_earned == 0)
    testing.expect(t, state.has_weather_briefing)
    testing.expect(t, state.has_clinic_satchel)
    testing.expect(t, state.has_dry_wrap)
    testing.expect(t, state.has_recovery_kit)
}

@(test)
resident_errands_do_not_overwrite_active_cargo :: proc(t: ^testing.T) {
    state: story.State
    receive_friendometer(t, &state)
    testing.expect(t, story.begin_post_delivery(&state))
    testing.expect(t, !story.begin_local_delivery(&state, .Clinic_Medicine))
    testing.expect(t, state.delivery.kind == .Repeat_Eastbound)
}

@(test)
resident_errands_are_playable_through_dialogue_choices :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)

    weather_state: story.State
    receive_friendometer(t, &weather_state)
    zora, zora_opened := dialogue.open(&catalog.zora, {data = rawptr(&weather_state)})
    testing.expect(t, zora_opened)
    testing.expect(t, dialogue.choose(&zora, 4))
    testing.expect(t, story.quest_is_active(&weather_state, .Weather_Reading))

    medicine_state: story.State
    receive_friendometer(t, &medicine_state)
    vesna, vesna_opened := dialogue.open(&catalog.vesna, {data = rawptr(&medicine_state)})
    testing.expect(t, vesna_opened)
    testing.expect(t, dialogue.choose(&vesna, 2))
    testing.expect(t, medicine_state.delivery.kind == .Clinic_Medicine)
    anica, anica_opened := dialogue.open(&catalog.anica, {data = rawptr(&medicine_state)})
    testing.expect(t, anica_opened)
    testing.expect(t, dialogue.choose(&anica, 2))
    testing.expect(t, medicine_state.medicine_delivered)

    linens_state: story.State
    receive_friendometer(t, &linens_state)
    petar, petar_opened := dialogue.open(&catalog.petar, {data = rawptr(&linens_state)})
    testing.expect(t, petar_opened)
    testing.expect(t, dialogue.choose(&petar, 2))
    testing.expect(t, linens_state.delivery.kind == .Clinic_Linens)
    anica, anica_opened = dialogue.open(&catalog.anica, {data = rawptr(&linens_state)})
    testing.expect(t, anica_opened)
    testing.expect(t, dialogue.choose(&anica, 2))
    testing.expect(t, linens_state.linens_delivered)

    water_state: story.State
    receive_friendometer(t, &water_state)
    anica, anica_opened = dialogue.open(&catalog.anica, {data = rawptr(&water_state)})
    testing.expect(t, anica_opened)
    testing.expect(t, dialogue.choose(&anica, 2))
    testing.expect(t, water_state.delivery.kind == .Clinic_Water)
    vesna, vesna_opened = dialogue.open(&catalog.vesna, {data = rawptr(&water_state)})
    testing.expect(t, vesna_opened)
    testing.expect(t, dialogue.choose(&vesna, 2))
    testing.expect(t, water_state.water_delivered)
}

@(test)
legacy_story_actions_publish_into_authoritative_quest_state :: proc(t: ^testing.T) {
    state: story.State
    receive_friendometer(t, &state)
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
    testing.expect(t, quest.first_active(&state.quest, &catalog.definition) == story.quest_node_id(.Friendometer))
    testing.expect(t, !quest.is_presented(&state.quest, &catalog.definition, story.quest_node_id(.Magneto_Westbound)))
    testing.expect(t, !story.begin_delivery(&state))
    testing.expect(t, !story.report_crash(&state))

    receive_friendometer(t, &state)
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
marta_and_gerta_remember_the_magneto_errand_without_flattening_their_difference :: proc(t: ^testing.T) {
    testing.expect(
        t,
        story.magneto_memory_text(.Marta) ==
        "Il replacement magneto parte avant il caffè. Gerta chiama questo prova che aveva raison; io, che il vecchio meritava pensione con onore.",
    )
    testing.expect(
        t,
        story.magneto_memory_text(.Gerta) ==
        "Marta rapporte che il replacement magneto parte al primo tiraggio. Per lei prova la maintenance; curiosamente, prova aussi la mia replacement.",
    )

    testing.expect(
        t,
        story.magneto_opinion_text(.Marta, .Marta) ==
        "Esatto. Due estati extra da un cracked magneto non sono ostinazione; sono planification prudente della pensione. Dillo a Gerta lentamente.",
    )
    testing.expect(
        t,
        story.magneto_opinion_text(.Marta, .Gerta) ==
        "Aussi vero. Gerta ha trouvé la replacement corretta avant che ammettessi il bisogno. Una sister può avere raison senza una parade.",
    )
    testing.expect(
        t,
        story.magneto_opinion_text(.Gerta, .Marta) ==
        "Correct. Marta ha sentito la crack avant ogni instrument e l'ha tenuta sicura fino alla replacement. Lo concederò in scrittura très piccola.",
    )
    testing.expect(
        t,
        story.magneto_opinion_text(.Gerta, .Gerta) ==
        "Ja. Serie corretta, timing corretto, delivery asciutta. Mais se Marta domanda, dite solo che la machine ha deciso indépendamment.",
    )
    testing.expect(
        t,
        story.magneto_accept_careful_text() ==
        "Bene. Oilcloth intorno al metal, knot lontano dai terminals, und broken magneto sopra lo spray. Gerta apprécie i nomi corretti.",
    )
    testing.expect(
        t,
        story.magneto_accept_inspection_text() ==
        "Solo corrieri con calze bagnate. Arriva asciutto, di' broken magneto avant ogni storia, et forse inspecta solo il knot.",
    )
    testing.expect(
        t,
        story.magneto_handoff_crack_text() ==
        "Ja. Sotto olio pulito, la crack continua plus lontano di quanto confessava. Stessa serie, replacement corretta, und zero estati prestito.",
    )
    testing.expect(
        t,
        story.magneto_handoff_marta_text() ==
        "Abbastanza lunga da provare che sentiva la machine correttamente. Marta dice maintenance; io, affection con una torque wrench.",
    )
    testing.expect(
        t,
        story.magneto_return_dry_text() ==
        "Perfetto. Coils asciutte, terminals puliti, und zero sale. Gerta diffida dei corrieri, mais prepara il loro successo.",
    )
    testing.expect(
        t,
        story.magneto_return_knot_text() ==
        "Naturalmente. Due giri, un square knot, et una coda abbastanza lunga per criticare. Mia sister scrive instructions anche con lo spago.",
    )
}

@(test)
marta_and_gerta_answer_local_news_with_distinct_temperaments :: proc(t: ^testing.T) {
    testing.expect(
        t,
        story.airfield_news_warm_text(.Marta) ==
        "Piano va bene. Un faro, un forno, und persone puniscono tutti la fretta—solo il repair manual lo ammette.",
    )
    testing.expect(
        t,
        story.airfield_news_warm_text(.Gerta) ==
        "Ja. Niko planifica con farina, Iva mit meteo; tra loro, una traversata diventa pratica.",
    )
    testing.expect(
        t,
        story.airfield_news_discreet_text(.Marta) ==
        "Ogni runway, quai, und cucina ha testimoni. Fortunatamente, ciascuno è occupato a prétendre il contrario.",
    )
    testing.expect(
        t,
        story.airfield_news_discreet_text(.Gerta) ==
        "Isole piccole, sightlines lunghe, et zero veri segreti. La privacy sopravvive perché chacun perde un fatto.",
    )
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
