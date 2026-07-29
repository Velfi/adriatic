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
    }
    for label, index in labels {
        resident, found := story.resident_from_speaker(label)
        testing.expect(t, found && resident == expected[index])
    }
    _, found_unknown := story.resident_from_speaker("UNKNOWN")
    testing.expect(t, !found_unknown)
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
island_post_departures_include_cycle_aware_handoffs :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state: story.State
    ctx := dialogue.Context{data = rawptr(&state)}

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
    ctx := dialogue.Context{data = rawptr(&state)}

    testing.expect(t, story.begin_post_delivery(&state))
    lena, lena_opened := dialogue.open(&catalog.lena, ctx)
    testing.expect(t, lena_opened)
    testing.expect(t, dialogue.choose(&lena, 0))
    testing.expect(t, state.repeat_deliveries == 1 && !state.delivery.active)
    testing.expect(t, dialogue.current(&lena).id == "lena-receipt")
    testing.expect(
        t,
        dialogue.current(&lena).text(&lena.ctx) ==
            "Pane still soft, postcards flat, pressed flower intact. Toma put it inside a customs declaration; apparently tenderness now requires paperwork.",
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
            "Lamp glass whole, dinner note legible, pane wisely separate. Lena underlined SUPPER twice; this is no longer correspondence, it is navigation.",
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
        "I observed. Dry corners, straight stack, niente crushed. A postmaster notices care even when the ledger has no column for it.",
        "I observed. Weather reports flat, lamp glass whole, und no blue-pencil correction added en route. Excellent restraint.",
        "I observed. Glass below, note above, zero unauthorized basil. Even la watering-can accusation arrived unbent.",
    }
    toma_teasing := [3]string {
        "Officially, la lamp glass had priority. Unofficially, I read SUPPER before checking the crack. Do not revise the ledger.",
        "Lena returned every forecast con evidence. I inspected la blue pencil first—professional curiosity, naturellement.",
        "The watering can was very clear. La lamp glass merely confirmed the parcel survived while my reputation did not.",
    }
    lena_counts := [3]int{1, 3, 5}
    lena_orderly := [3]string {
        "I observed. Dry paper, soft pane, every corner respected. Care is the one postal mark nobody can counterfeit.",
        "I observed. Blue pencil dry, pane soft, postcards square. Even Toma's bite marks arrived exactly where recorded.",
        "I observed. Basil upright, roots damp, customs form absurdly flat. Care can survive bureaucracy, apparently.",
    }
    lena_teasing := [3]string {
        "Naturalmente. Toma supervises with both hands, then writes a form saying the parcel arranged itself. I shall file your testimony.",
        "Personally, yes. He wrapped la pencil like crown jewels, puis denied every tooth mark in triplicate.",
        "Toma supervised the basil until it acquired paperwork. I shall water la plant and archive his anxiety.",
    }
    for index in 0 ..< 3 {
        toma_state := story.State{repeat_deliveries = toma_counts[index]}
        toma_ctx := dialogue.Context{data = rawptr(&toma_state)}
        testing.expect(t, story.toma_post_orderly_close(&toma_ctx) == toma_orderly[index])
        testing.expect(t, story.toma_post_teasing_close(&toma_ctx) == toma_teasing[index])

        lena_state := story.State{repeat_deliveries = lena_counts[index]}
        lena_ctx := dialogue.Context{data = rawptr(&lena_state)}
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
        []string {
            "I'll keep it dry and in order.",
            "I'll ignore any personal evidence.",
        },
    )
    expect_choice_texts(
        t,
        catalog.niko_handoff_close_choices[:],
        []string{"East island, then."},
    )
    expect_choice_texts(
        t,
        catalog.niko_together_choices[:],
        []string{"You found a good rhythm.", "I'll call the experiment successful."},
    )
    expect_choice_texts(
        t,
        catalog.niko_together_close_choices[:],
        []string{"I'll leave the scheduling to you."},
    )
    expect_choice_texts(
        t,
        catalog.meeting_choices[:],
        []string{"The awning suits you both.", "I saw only an ordinary arrival."},
    )
    expect_choice_texts(
        t,
        catalog.meeting_warm_choices[:],
        []string{"And enough bread for a delayed plane."},
    )
    expect_choice_texts(
        t,
        catalog.meeting_discreet_choices[:],
        []string{"I can forget the landing, not the bread."},
    )
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
        []string {
            "I'll keep everything dry and intact.",
            "I'll follow your packing instructions.",
        },
    )
    expect_choice_texts(
        t,
        catalog.iva_handoff_close_choices[:],
        []string{"West island, then."},
    )
    expect_choice_texts(
        t,
        catalog.iva_together_choices[:],
        []string{"The system seems to suit you both.", "I'll trust your evidence."},
    )
    expect_choice_texts(
        t,
        catalog.iva_together_close_choices[:],
        []string{"I'll leave you to the next crossing."},
    )
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
        []string {
            "The rib is sound; only the canvas tore.",
            "The ground signed its name here.",
        },
    )
    expect_choice_texts(
        t,
        catalog.bojan_inspect_close_choices[:],
        []string{"Let's fit the canvas patch."},
    )
    expect_choice_texts(t, catalog.bojan_patch_choices[:], []string{"Let's test the controls."})
    expect_choice_texts(
        t,
        catalog.bojan_repair_choices[:],
        []string {
            "The controls move cleanly.",
            "All three wheels survived.",
        },
    )
    expect_choice_texts(
        t,
        catalog.bojan_repair_close_choices[:],
        []string{"Then the aeroplano is ready."},
    )
    expect_choice_texts(
        t,
        catalog.bojan_check_choices[:],
        []string {
            "Show me the inspection marks.",
            "The patch outperforms its pilot.",
        },
    )
    expect_choice_texts(
        t,
        catalog.bojan_check_close_choices[:],
        []string{"Keep it out of the ground."},
    )
    expect_choice_texts(
        t,
        catalog.zora_choices[:],
        []string {
            "Which way is the wind blowing?",
            "Past, present, and possible shore.",
            "I have time. Lay out the full cross.",
            "Remind me what I should watch for.",
            "Another time, grazie.",
        },
    )
    expect_choice_texts(
        t,
        catalog.zora_reading_choices[:],
        []string{"What should I watch for?", "Enough cards. I'll watch the real sky."},
    )
    expect_choice_texts(
        t,
        catalog.zora_counsel_choices[:],
        []string{"Then I'll choose the next crossing."},
    )
    expect_choice_texts(
        t,
        catalog.zora_recall_choices[:],
        []string {
            "I'll act before asking the cards again.",
            "I'll trust the sky more than the cards.",
        },
    )
    expect_choice_texts(
        t,
        catalog.zora_recall_close_choices[:],
        []string{"Then I'll get moving."},
    )
    expect_choice_texts(
        t,
        catalog.vesna_choices[:],
        []string {
            "Thanks, doctor. I'll take it slower.",
            "The landing looked softer from above.",
            "I checked the weather. It wasn't enough.",
            "I remembered where my glasses go.",
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
        },
    )
    expect_choice_texts(
        t,
        catalog.anica_close_choices[:],
        []string{"I'll make the next appointment quieter."},
    )
    expect_choice_texts(
        t,
        catalog.toma_handoff_choices[:],
        []string {
            "I'll follow the ledger exactly.",
            "I'll improvise if the sea does.",
        },
    )
    expect_choice_texts(
        t,
        catalog.toma_handoff_close_choices[:],
        []string{"Eastbound, then."},
    )
    expect_choice_texts(
        t,
        catalog.toma_receipt_choices[:],
        []string {
            "Everything stayed in its proper place.",
            "The supper note outranked the glass.",
        },
    )
    expect_choice_texts(t, catalog.toma_close_choices[:], []string{"Your ledger is safe with me."})
    expect_choice_texts(
        t,
        catalog.lena_handoff_choices[:],
        []string {
            "I'll keep Toma's post in order.",
            "I'll make sure he reads SUPPER first.",
        },
    )
    expect_choice_texts(
        t,
        catalog.lena_handoff_close_choices[:],
        []string{"Westbound, then."},
    )
    expect_choice_texts(
        t,
        catalog.lena_receipt_choices[:],
        []string {
            "Everything stayed dry and flat.",
            "Toma supervised every item personally.",
        },
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
            "The blue awning is exactly where Niko described it. Bojan calls il volo routine, mais routine landings use tutte three wheels, sì?",
    )
    testing.expect(
        t,
        story.meeting_niko_warm(nil) ==
            "The third wheel was decorative. Siediti, per favore; io made enough pane pour una regatta and one delayed aeroplano.",
    )
    testing.expect(
        t,
        story.meeting_iva_warm_close(nil) ==
            "He counted il pane twice und les minutes three times. I arrived before either ran out.",
    )
    testing.expect(
        t,
        story.meeting_niko_discreet(nil) ==
            "Then you saw nothing, grazie. Only un baker, una lighthouse keeper, und lunch beneath an ordinary awning.",
    )
    testing.expect(
        t,
        story.meeting_iva_discreet_close(nil) ==
            "A very ordinary awning. Niko polished la frame ieri—due times, mit complete indifference.",
    )

    catalog: story.Catalog
    story.init_catalog(&catalog)
    state := story.State{romance = .Meeting, repair = .Repaired}
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
    state := story.State{romance = .Together, repeat_deliveries = 2}
    ctx := dialogue.Context{data = rawptr(&state)}

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
    state := story.State{clinic_visits = 1}
    ctx := dialogue.Context{data = rawptr(&state), location_id = "clinic"}

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
clinic_residents_change_the_conversation_on_repeat_visits :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    state := story.State{clinic_visits = 3}
    ctx := dialogue.Context{data = rawptr(&state), location_id = "clinic"}

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
    states := [3]story.State {
        {clinic_visits = 2},
        {clinic_visits = 3},
        {clinic_visits = 4},
    }
    vesna_expected := [3]string {
        "Visit numero 2. Same pilot, new bruise, und familiar glasses. Bene: acqua first; then we compare your story with il meteo.",
        "Visit numero 3. You know la routine: acqua, repos, then inspect il meteo before the motor.",
        "Visit numero 4. La tray remembered your glasses; io prefer when patients learn faster than furniture. Acqua, repos, meteo.",
    }
    petar_expected := [3]string {
        "Visit numero 2. La scarf is dry, the door remains innocent, und your aeroplano waits outside. In questo order.",
        "Visit numero 3. Your glasses found la tray without assistance. I wish il pilot showed equal navigation.",
        "Visit numero 4. Una dry scarf, due clean sheets, und zero applause. Vesna handles medicine; io protect the linens.",
    }
    anica_expected := [3]string {
        "Again, numero 2. I moved the acqua closer and la appointment book farther away. One of us is learning.",
        "Again you, visit numero 3. Il mare pardons beaucoup, but it does not keep my records.",
        "Visit numero 4. Acqua waits by the bed, meteo waits on the wall, und il mare waits for nobody. Choose the first.",
    }
    for index in 0 ..< len(states) {
        ctx := dialogue.Context{data = rawptr(&states[index]), location_id = "clinic"}
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
        dialogue.current(&conversation).text(&conversation.ctx) ==
            story.bojan_inspect_practical_close(nil),
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
        state := story.State{repair = .Crash_Reported}
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
        dialogue.available_at(&iva_conversation, 0).text == "I'll take Niko the regatta acceptance.",
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
marta_and_gerta_remember_the_magneto_errand_without_flattening_their_difference :: proc(t: ^testing.T) {
    testing.expect(
        t,
        story.magneto_memory_text(.Marta) ==
            "The replacement magneto starts before my coffee now. Gerta calls this proof she was right; io call it proof the old one deserved retirement with honors.",
    )
    testing.expect(
        t,
        story.magneto_memory_text(.Gerta) ==
            "Marta reports the replacement magneto starts first pull. She says this proves her maintenance was correct. Curiously, it also proves my replacement was correct.",
    )

    testing.expect(
        t,
        story.magneto_opinion_text(.Marta, .Marta) ==
            "Esatto. Two extra summers from one cracked magneto is not stubbornness; it is careful retirement planning. Tell Gerta slowly.",
    )
    testing.expect(
        t,
        story.magneto_opinion_text(.Marta, .Gerta) ==
            "Also true. Gerta found the right replacement before I admitted needing it. Una sister may be correct without receiving a parade.",
    )
    testing.expect(
        t,
        story.magneto_opinion_text(.Gerta, .Marta) ==
            "Fair. Marta heard the crack before any instrument did and kept it safe until replacement. I shall concede this in very small handwriting.",
    )
    testing.expect(
        t,
        story.magneto_opinion_text(.Gerta, .Gerta) ==
            "Ja. Correct series, correct timing, dry delivery. But if Marta asks, say only that la machine made an independent decision.",
    )
    testing.expect(
        t,
        story.magneto_accept_careful_text() ==
            "Bene. Oilcloth around il metal, knot away from the terminals, und broken magneto above the spray. Gerta appreciates correct nouns.",
    )
    testing.expect(
        t,
        story.magneto_accept_inspection_text() ==
            "Only couriers with wet socks. Arrive asciutto, say 'broken magneto' before any story, et she may inspect merely your knot.",
    )
    testing.expect(
        t,
        story.magneto_handoff_crack_text() ==
            "Ja. Under clean oil, la crack runs farther than it confessed. Same series, correct replacement, und no more borrowed summers.",
    )
    testing.expect(
        t,
        story.magneto_handoff_marta_text() ==
            "Long enough to prove she heard la machine correctly. Marta calls it maintenance; io call it affection with a torque wrench.",
    )
    testing.expect(
        t,
        story.magneto_return_dry_text() ==
            "Perfetto. Dry coils, clean terminals, und zero salt. Gerta may distrust couriers, but she packs for their success.",
    )
    testing.expect(
        t,
        story.magneto_return_knot_text() ==
            "Of course. Due turns, one square knot, et a tail long enough to criticize. My sister writes instructions even in string.",
    )
}

@(test)
marta_and_gerta_answer_local_news_with_distinct_temperaments :: proc(t: ^testing.T) {
    testing.expect(
        t,
        story.airfield_news_warm_text(.Marta) ==
            "Piano is good. Una lighthouse, un forno, und persone all punish haste—only the repair manual admits it.",
    )
    testing.expect(
        t,
        story.airfield_news_warm_text(.Gerta) ==
            "Ja. Niko plans con flour, Iva mit meteo; between them, una crossing becomes practical.",
    )
    testing.expect(
        t,
        story.airfield_news_discreet_text(.Marta) ==
            "Every runway, quai, und cucina has witnesses. Fortunately, ciascuno is busy pretending otherwise.",
    )
    testing.expect(
        t,
        story.airfield_news_discreet_text(.Gerta) ==
            "Small islands, lange sightlines, et zero true secrets. Privacy survives because everyone misplaces one fact.",
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
