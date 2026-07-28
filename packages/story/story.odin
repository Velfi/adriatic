package story

import dialogue "../dialogue"
import quest "../quest"
import tarot "../tarot"
import "core:fmt"

// A small two-island story campaign. The owning game decides where residents
// stand and how rewards are presented; this package owns narrative progression.

Island :: enum {
    West,
    East,
}

Resident :: enum {
    Marta,
    Gerta,
    Niko,
    Iva,
    Bojan,
    Zora,
    Vesna,
    Petar,
    Anica,
    Toma,
    Lena,
}

Romance_Stage :: enum {
    Unintroduced,
    First_Letter,
    Corresponding,
    Invitation,
    Meeting,
    Together,
}

Repair_Stage :: enum {
    Not_Seen,
    Crash_Reported,
    Diagnosed,
    Patched,
    Repaired,
}

Airfield_Errand_Stage :: enum {
    Not_Offered,
    Westbound,
    Eastbound,
    Completed,
}

Delivery_Kind :: enum {
    None,
    First_Letter,
    First_Reply,
    Regatta_Invitation,
    Regatta_Acceptance,
    Repeat_Eastbound,
    Repeat_Westbound,
}

Delivery :: struct {
    active:      bool,
    kind:        Delivery_Kind,
    from, to:    Resident,
    origin:      Island,
    destination: Island,
    subject:     string,
}

State :: struct {
    quest:                quest.State,
    romance:              Romance_Stage,
    repair:               Repair_Stage,
    airfield_errand:      Airfield_Errand_Stage,
    delivery:             Delivery,
    completed_deliveries: int,
    repeat_deliveries:    int,
    stamps_earned:        int,
    has_wing_patch:       bool,
    tarot_readings:       int,
    tarot_seed:           u32,
    tarot_last_moment:    u32,
    tarot_layout:         tarot.Layout,
    clinic_visits:        int,
    // Quest punctuation is a notification, not a permanent label. Remember
    // the action state last seen in conversation so it stays gone until that
    // resident has something new to say or do.
    resident_action_seen: [Resident]u64,
}

resident_name :: proc(resident: Resident) -> string {
    switch resident {
    case .Marta:
        return "Marta"
    case .Gerta:
        return "Gerta"
    case .Niko:
        return "Niko"
    case .Iva:
        return "Iva"
    case .Bojan:
        return "Bojan"
    case .Zora:
        return "Zora"
    case .Vesna:
        return "Dr Vesna"
    case .Petar:
        return "Petar"
    case .Anica:
        return "Anica"
    case .Toma:
        return "Toma"
    case .Lena:
        return "Lena"
    }
    return ""
}

resident_island :: proc(resident: Resident) -> Island {
    switch resident {
    case .Marta, .Iva, .Lena:
        return .East
    case .Gerta, .Niko, .Bojan, .Toma:
        return .West
    case .Zora:
        return .East
    case .Vesna:
        return .West
    case .Petar:
        return .West
    case .Anica:
        return .East
    }
    return .West
}

begin_delivery :: proc(state: ^State) -> bool {
    if state == nil || state.delivery.active do return false
    _ = ensure_quest_progress(state)

    delivery: Delivery
    switch state.romance {
    case .Unintroduced:
        catalog: Quest_Catalog
        init_quest_catalog(&catalog)
        if !quest.accept(&state.quest, &catalog.definition, quest_node_id(.First_Letter)) do return false
        delivery = {
            active      = true,
            kind        = .First_Letter,
            from        = .Niko,
            to          = .Iva,
            origin      = .West,
            destination = .East,
            subject     = "A recipe for a clear morning",
        }
    case .First_Letter:
        delivery = {
            active      = true,
            kind        = .First_Reply,
            from        = .Iva,
            to          = .Niko,
            origin      = .East,
            destination = .West,
            subject     = "The lighthouse keeper's reply",
        }
    case .Corresponding:
        delivery = {
            active      = true,
            kind        = .Regatta_Invitation,
            from        = .Niko,
            to          = .Iva,
            origin      = .West,
            destination = .East,
            subject     = "An invitation for the regatta",
        }
    case .Invitation:
        if state.repair != .Repaired do return false
        delivery = {
            active      = true,
            kind        = .Regatta_Acceptance,
            from        = .Iva,
            to          = .Niko,
            origin      = .East,
            destination = .West,
            subject     = "Meet me beneath the blue awning",
        }
    case .Meeting:
        return false
    case .Together:
        return begin_post_delivery(state)
    }
    state.delivery = delivery
    return true
}

begin_post_delivery :: proc(state: ^State) -> bool {
    if state == nil || state.delivery.active || !ensure_quest_progress(state) do return false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)
    if quest.status(&state.quest, &catalog.definition, quest_node_id(.Post_Route)) != .Active do return false

    eastbound := state.repeat_deliveries % 2 == 0
    state.delivery = eastbound ? Delivery {
        active      = true,
        kind        = .Repeat_Eastbound,
        from        = .Toma,
        to          = .Lena,
        origin      = .West,
        destination = .East,
        subject     = "Bread, postcards, and one pressed flower",
    } : Delivery {
        active      = true,
        kind        = .Repeat_Westbound,
        from        = .Lena,
        to          = .Toma,
        origin      = .East,
        destination = .West,
        subject     = "Lamp glass and a note for supper",
    }
    return true
}

complete_delivery :: proc(state: ^State, recipient: Resident) -> bool {
    if state == nil || !state.delivery.active || state.delivery.to != recipient do return false

    event: quest.Event
    switch state.delivery.kind {
    case .First_Letter:
        if state.romance != .Unintroduced do return false
        event = {
            kind   = .Deliver,
            key    = "first-letter",
            target = "iva",
        }
    case .First_Reply:
        if state.romance != .First_Letter do return false
        event = {
            kind   = .Deliver,
            key    = "first-reply",
            target = "niko",
        }
    case .Regatta_Invitation:
        if state.romance != .Corresponding do return false
        event = {
            kind   = .Deliver,
            key    = "regatta-invitation",
            target = "iva",
        }
    case .Regatta_Acceptance:
        if state.romance != .Invitation || state.repair != .Repaired do return false
        event = {
            kind   = .Deliver,
            key    = "regatta-acceptance",
            target = "niko",
        }
    case .Repeat_Eastbound, .Repeat_Westbound:
        event = {
            kind = .Deliver,
            key  = "post-route",
        }
    case .None:
        return false
    }
    update, published := publish_quest_event(state, event)
    if !published || update.completed_count == 0 do return false

    state.delivery.active = false
    return true
}

complete_meeting :: proc(state: ^State) -> bool {
    if state == nil || state.romance != .Meeting || state.delivery.active do return false
    update, published := publish_quest_event(state, {kind = .Talk, key = "awning-meeting"})
    return published && update.completed_count > 0
}

report_crash :: proc(state: ^State) -> bool {
    if state == nil || state.repair != .Not_Seen do return false
    if !ensure_quest_progress(state) do return false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)
    if !quest.accept(&state.quest, &catalog.definition, quest_node_id(.Crash_Reported)) do return false
    update, published := publish_quest_event(state, {kind = .Talk, key = "crash-reported", target = "bojan"})
    return published && update.completed_count > 0
}

accept_airfield_errand :: proc(state: ^State) -> bool {
    if state == nil || state.airfield_errand != .Not_Offered do return false
    if !ensure_quest_progress(state) do return false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)
    if !quest.accept(&state.quest, &catalog.definition, quest_node_id(.Magneto_Westbound)) do return false
    state.airfield_errand = .Westbound
    return true
}

handoff_broken_magneto :: proc(state: ^State) -> bool {
    if state == nil || state.airfield_errand != .Westbound do return false
    update, published := publish_quest_event(state, {kind = .Deliver, key = "broken-magneto", target = "gerta"})
    return published && update.completed_count > 0
}

return_replacement_magneto :: proc(state: ^State) -> bool {
    if state == nil || state.airfield_errand != .Eastbound do return false
    update, published := publish_quest_event(state, {kind = .Deliver, key = "replacement-magneto", target = "marta"})
    return published && update.completed_count > 0
}

diagnose_crash :: proc(state: ^State) -> bool {
    if state == nil || state.repair != .Crash_Reported do return false
    update, published := publish_quest_event(state, {kind = .Inspect, key = "bojan-wing"})
    if !published || update.completed_count == 0 do return false
    state.has_wing_patch = true
    return true
}

apply_wing_patch :: proc(state: ^State) -> bool {
    if state == nil || state.repair != .Diagnosed || !state.has_wing_patch do return false
    update, published := publish_quest_event(state, {kind = .Repair, key = "apply-wing-patch"})
    if !published || update.completed_count == 0 do return false
    state.has_wing_patch = false
    return true
}

verify_repair :: proc(state: ^State) -> bool {
    if state == nil || state.repair != .Patched do return false
    update, published := publish_quest_event(state, {kind = .Repair, key = "verify-wing-repair"})
    return published && update.completed_count > 0
}

state_from_context :: proc(ctx: ^dialogue.Context) -> ^State {
    if ctx == nil || ctx.data == nil do return nil
    return cast(^State)ctx.data
}

niko_speaker :: proc(_: ^dialogue.Context) -> string { return "NIKO" }
iva_speaker :: proc(_: ^dialogue.Context) -> string { return "IVA" }
bojan_speaker :: proc(_: ^dialogue.Context) -> string { return "BOJAN" }
zora_speaker :: proc(_: ^dialogue.Context) -> string { return "ZORA" }
vesna_speaker :: proc(_: ^dialogue.Context) -> string { return "DR VESNA" }
petar_speaker :: proc(_: ^dialogue.Context) -> string { return "PETAR" }
anica_speaker :: proc(_: ^dialogue.Context) -> string { return "ANICA" }

vesna_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.clinic_visits == 0 {
        return "La clinica is quiet, dobro. Mais we keep un letto pronto, perché pilots confuse fortuna con meteo."
    }
    if state.clinic_visits == 1 {
        return "Niente rotto. Un po' de riposo, beaucoup d'acqua, und oggi no bravura. Tes lunettes sono sul vassoio."
    }
    return fmt.tprintf(
        "Visita numero %d. Tu connais la routine: acqua, repos, then guarda il meteo before il motore.",
        state.clinic_visits,
    )
}

petar_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.clinic_visits == 0 {
        return "Io wash le lenzuola ogni mattina. Das is not une invitation à remplirle il letto, capito?"
    }
    return(
        "Tes lunettes sont sul vassoio, le scarf est asciutta, und il tuo aeroplano aspetta all'airfield. In quest'ordine." \
    )
}

anica_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.clinic_visits == 0 {
        return(
            "La clinica east guarda il mare. Dobro for finding boats; moins dobro quand un aeroplano arrive senza appuntamento." \
        )
    }
    if state.clinic_visits == 1 {
        return(
            "Respira piano. Rien de cassé, samo un grande rumore. Ho messo acqua qui und il meteo là—scegli prima l'acqua." \
        )
    }
    return fmt.tprintf(
        "Ancora tu, visita numero %d. Il mare forgives beaucoup, aber non tiene il conto per me.",
        state.clinic_visits,
    )
}

zora_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.tarot_readings == 0 {
        return(
            "Ferme la persiana, piccolo corriere. The bura mescola déjà abbastanza. Le carte ne commandent pas il mare; they show seulement dove tira il vento." \
        )
    }
    if state.tarot_last_moment == tarot_moment(state) {
        return "Le carte ont parlé pour questo vento. Now guarda il cielo vero; ritorna quand qualcosa cambia."
    }
    return "Siedi. The vento ha tourné depuis l'ultima volta; vediamo si les cartes l'hanno notato."
}

tarot_moment :: proc(state: ^State) -> u32 {
    if state == nil do return 0
    return u32(state.romance) * 8 + u32(state.repair) + 1
}

can_deal_tarot :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && (state.tarot_readings == 0 || state.tarot_last_moment != tarot_moment(state))
}

tarot_card_omen :: proc(card: tarot.Card) -> string {
    id := int(card)
    switch {
    case id == 6:
        return "deux persone must scegliere la stessa traversée"
    case id == 7:
        return "the voyage demande mani ferme, non fretta"
    case id == 9:
        return "une lampe solitaria can ancora guidare qualcuno"
    case id == 10:
        return "the ruota tourne, mais seulement si qualcuno la spinge"
    case id == 16:
        return "ce qui looks like rovina demande prima un'ispezione"
    case id == 17:
        return "une luce lontana is aussi una promessa"
    case id == 18:
        return "the meteo cache metà della route"
    case id == 19:
        return "la clarté will arrivare con il giorno"
    case id >= 22 && id < 36:
        return "le travail e il coraggio pull nella stessa direzione"
    case id >= 36 && id < 50:
        return "les affetti travel meglio in un recipiente semplice"
    case id >= 50 && id < 64:
        return "une parola cuts; una parola precisa répare"
    case id >= 64:
        return "the cosa concreta sotto la mano mérite confiance"
    }
    return "le changement is già entrato dalla finestra"
}

zora_story_omen :: proc(state: ^State) -> string {
    if state == nil do return "Ne cours pas dietro al simbolo; watch cosa fa muovere."
    switch state.romance {
    case .Unintroduced:
        return "Deux persone keep le stesse ore su rive diverse. Non la chiamano encore attesa."
    case .First_Letter:
        return "Une cosa sigillata crosses meglio il mare in mani che savent se taire."
    case .Corresponding:
        return "Les distanze become piccole prima sulla carta, puis sotto i piedi."
    case .Invitation:
        if state.repair != .Repaired {
            return "Canvas, vento, et un voyage da réparer prima di prometterlo."
        }
        return "La route nel cielo is pronta. Il coraggio doit seulement salire a bordo."
    case .Meeting:
        return "Deux sedie sous una tenda blu make moins ombra di una sedia vuota."
    case .Together:
        return "Tu connais the route: pane all'andata, verre ben avvolto al ritorno."
    }
    return ""
}

zora_reading_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.tarot_layout.count == 0 do return "La table is vuota; qualcosa ha mangé la sorte."
    first := state.tarot_layout.placements[0]
    direction := first.orientation == .Reversed ? "controvento" : "con il vento"
    switch state.tarot_layout.spread {
    case .Single:
        return fmt.tprintf(
            "%s, %s: %s.\n%s",
            tarot.card_name(first.card),
            direction,
            tarot_card_omen(first.card),
            zora_story_omen(state),
        )
    case .Three_Card:
        second := state.tarot_layout.placements[1]
        third := state.tarot_layout.placements[2]
        return fmt.tprintf(
            "Passé: %s. Ora: %s.\nPossible shore: %s. %s",
            tarot.card_name(first.card),
            tarot.card_name(second.card),
            tarot.card_name(third.card),
            zora_story_omen(state),
        )
    case .Celtic_Cross:
        crossing := state.tarot_layout.placements[1]
        shore := state.tarot_layout.placements[state.tarot_layout.count - 1]
        return fmt.tprintf(
            "Cœur: %s. Contro: %s.\nFar shore, riva lontana: %s. %s",
            tarot.card_name(first.card),
            tarot.card_name(crossing.card),
            tarot.card_name(shore.card),
            zora_story_omen(state),
        )
    }
    return ""
}

deal_tarot :: proc(ctx: ^dialogue.Context, spread: tarot.Spread) {
    state := state_from_context(ctx)
    if state == nil do return
    if state.tarot_seed == 0 do state.tarot_seed = 0x5a4f5241
    state.tarot_layout = tarot.deal(spread, state.tarot_seed)
    state.tarot_readings += 1
    state.tarot_last_moment = tarot_moment(state)
    state.tarot_seed = state.tarot_seed * 1664525 + 1013904223
}

deal_single :: proc(ctx: ^dialogue.Context) { deal_tarot(ctx, .Single) }
deal_three :: proc(ctx: ^dialogue.Context) { deal_tarot(ctx, .Three_Card) }
deal_cross :: proc(ctx: ^dialogue.Context) { deal_tarot(ctx, .Celtic_Cross) }

niko_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Buongiorno. Die forni will be chauds avant che il porto si svegli."
    if state.delivery.active && state.delivery.to == .Niko {
        switch state.delivery.kind {
        case .First_Reply:
            return "Ah, du bist back across il mare. Tu as Iva's reply con te?"
        case .Regatta_Acceptance:
            return "Bojan's moteur crossed la baia à l'alba. Ist das Iva's regatta acceptance?"
        case .Repeat_Westbound:
            return "The lamp glass voyage malissimo. Hoffentlich Iva l'a packed meglio que moi."
        case .None, .First_Letter, .Regatta_Invitation, .Repeat_Eastbound:
        }
    }
    switch state.romance {
    case .Unintroduced:
        if state.airfield_errand == .Eastbound || state.airfield_errand == .Completed {
            return "Wenn tu retournes east… j'ai una sealed letter for Iva. Piccola fuori, almeno."
        }
        return "La lampe on l'isola est blinks twice avant alba. Iva veglia while meine forni warm."
    case .First_Letter:
        return "La boîte de cardamomo looks molto suspicious quand uno waits for risposta."
    case .Corresponding:
        return "La regatta needs un baker, certo. Questa regatta invitation is for Iva, gardienne du phare."
    case .Invitation:
        return "C'è una tenda blu am quai. Nobody sait pourquoi io la regarde toujours."
    case .Meeting:
        return "Iva hat trouvé the blue awning. It seems kleiner con due persone dessous."
    case .Together:
        return "The island post continua: Iva dit le verre può aspettare. Das pane cannot."
    }
    return ""
}

niko_delivery_reaction :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return ""
    switch state.delivery.kind {
    case .First_Reply:
        return "She ricordava la farina dans ma première nota. Non era la parte I expected."
    case .Regatta_Acceptance:
        return "Elle viene. Ich muss make la tenda look comme si non l'avessi lucidée."
    case .Repeat_Westbound:
        return "Le verre ha survécu, und elle included instructions per cena. One of them ist plus fragile."
    case .None, .First_Letter, .Regatta_Invitation, .Repeat_Eastbound:
        return "Grazie. Certaines cose arrivent meglio wenn niemand le abre en route."
    }
    return ""
}

niko_warm_close :: proc(_: ^dialogue.Context) -> string {
    return "Va bene. Ich stelle un altro plateau dentro; waiting va mieux con lavoro utile."
}

niko_discreet_close :: proc(_: ^dialogue.Context) -> string {
    return "Bene. Una lettre sigillata mérite almeno una persona who can keep silent."
}

meeting_iva_text :: proc(_: ^dialogue.Context) -> string {
    return "Bojan appelle le vol routine. But routine landings use tutte le ruote, sì?"
}

meeting_niko_warm :: proc(_: ^dialogue.Context) -> string {
    return "Bleib pour la première course. I made troppo pane mit remarquable foresight."
}

meeting_niko_discreet :: proc(_: ^dialogue.Context) -> string {
    return "Ti dobbiamo une traversée tranquille, sans questions. Auch cena, if le mare te donne faim."
}

iva_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Dobro jutro. La lampe is prête; il meteo ne sait pas yet."
    if state.delivery.active && state.delivery.to == .Iva {
        switch state.delivery.kind {
        case .First_Letter:
            return "Una sealed letter crossed tutto quel mare bleu pour trouver ce phare."
        case .Regatta_Invitation:
            return "Niko's regatta invitation devient straighter quand lui prétend non essere nervous."
        case .Repeat_Eastbound:
            return "The island post smells comme si Niko confused la route postale con una pantry."
        case .None, .First_Reply, .Regatta_Acceptance, .Repeat_Westbound:
        }
    }
    switch state.romance {
    case .Unintroduced:
        return "Due lampi signifient acqua chiara. One looked toujours un poco solo."
    case .First_Letter:
        return "He ricordava il cardamomo. Bene, le phare peut offrir Iva's reply."
    case .Corresponding:
        return "La posta dell'isola west has become remarquablement puntual."
    case .Invitation:
        if state.repair == .Repaired {
            return(
                "Tu repaired l'aereo de Bojan avant che io lo needed. Grazie; maintenant puoi portare la regatta acceptance." \
            )
        }
        return "Posso répondre à Niko, but l'ala rotta cannot carry me. Nema regatta yet."
    case .Meeting:
        return "L'isola west is plus bruyante que le phare. Niko, heureusement, non."
    case .Together:
        return "The island post porta pane, comme si il mare fosse un problema que feeding sempre résout."
    }
    return ""
}

iva_delivery_reaction :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return ""
    switch state.delivery.kind {
    case .First_Letter:
        return "He ricordava il cardamomo. Dite à Niko: due lampi, parce que one felt solo."
    case .Regatta_Invitation:
        if state.repair == .Repaired {
            return "L'aereo de Bojan is pronto. Grazie; ta gentillesse d'avant arranged ma risposta."
        }
        return "Io would go, mais l'aereo de Bojan shows more cielo through l'ala che sopra."
    case .Repeat_Eastbound:
        return "Pane, cartes postales und un fiore. He packed tre sortes de meteo."
    case .None, .First_Reply, .Regatta_Acceptance, .Repeat_Westbound:
        return "Encore sigillata. Grazie por traiter la traversée comme parte della promessa."
    }
    return ""
}

iva_warm_close :: proc(_: ^dialogue.Context) -> string {
    return "Don't sourire così al faro. Das encourages les mouettes."
}

iva_discreet_close :: proc(_: ^dialogue.Context) -> string {
    return "Grazie. Le isole are déjà petites sans que les lettres become strade pubbliche."
}

bojan_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "L'aeroplano und I faisons repos. Alles tranquillo, plus ou moins."
    switch state.repair {
    case .Not_Seen:
        return "L'atterraggio war perfekt. The ground est arrivé trop tôt. Hai visto nothing plus compliqué."
    case .Crash_Reported:
        return "Maintenant la versione officielle ist breve; we can inspect the wing honnêtement."
    case .Diagnosed:
        return "Uno panneau di tela is déchiré. Ich habe the canvas patch; tu as steadier mani que ma réputation."
    case .Patched:
        return "Canvas patch tendu, wing ribs straight, controles libres. Voilà: turn the propeller, con prudenza."
    case .Repaired:
        if state.romance == .Invitation {
            return "L'aereo is pronto pour Iva. Ich habe même cleaned il seat qui non m'appartient."
        }
        return "Patch tendu, wing ribs straight, controles libres. Basta—that is notre ingénierie."
    }
    return ""
}

accept_delivery :: proc(ctx: ^dialogue.Context) { _ = begin_delivery(state_from_context(ctx)) }
accept_post_delivery :: proc(ctx: ^dialogue.Context) { _ = begin_post_delivery(state_from_context(ctx)) }
complete_toma_delivery :: proc(ctx: ^dialogue.Context) { _ = complete_delivery(state_from_context(ctx), .Toma) }
complete_lena_delivery :: proc(ctx: ^dialogue.Context) { _ = complete_delivery(state_from_context(ctx), .Lena) }
complete_niko_delivery :: proc(ctx: ^dialogue.Context) { _ = complete_delivery(state_from_context(ctx), .Niko) }
complete_iva_delivery :: proc(ctx: ^dialogue.Context) { _ = complete_delivery(state_from_context(ctx), .Iva) }
finish_meeting :: proc(ctx: ^dialogue.Context) { _ = complete_meeting(state_from_context(ctx)) }
note_crash :: proc(ctx: ^dialogue.Context) { _ = report_crash(state_from_context(ctx)) }
inspect_crash :: proc(ctx: ^dialogue.Context) { _ = diagnose_crash(state_from_context(ctx)) }
patch_wing :: proc(ctx: ^dialogue.Context) { _ = apply_wing_patch(state_from_context(ctx)) }
confirm_repair :: proc(ctx: ^dialogue.Context) { _ = verify_repair(state_from_context(ctx)) }

can_begin_niko_delivery :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    if state == nil || state.delivery.active do return false
    if state.romance == .Unintroduced {
        if !ensure_quest_progress(state) do return false
        catalog: Quest_Catalog
        init_quest_catalog(&catalog)
        return quest.status(&state.quest, &catalog.definition, quest_node_id(.First_Letter)) == .Available
    }
    return state.romance == .Corresponding || (state.romance == .Together && state.repeat_deliveries % 2 == 0)
}

can_begin_iva_delivery :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    if state == nil || state.delivery.active do return false
    return(
        state.romance == .First_Letter ||
        (state.romance == .Invitation && state.repair == .Repaired) ||
        (state.romance == .Together && state.repeat_deliveries % 2 == 1) \
    )
}

can_complete_niko_delivery :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.delivery.active && state.delivery.to == .Niko
}

can_complete_iva_delivery :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.delivery.active && state.delivery.to == .Iva
}

delivery_is :: proc(ctx: ^dialogue.Context, kind: Delivery_Kind) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.delivery.active && state.delivery.kind == kind
}

has_first_reply :: proc(ctx: ^dialogue.Context) -> bool { return delivery_is(ctx, .First_Reply) }
has_regatta_acceptance :: proc(ctx: ^dialogue.Context) -> bool { return delivery_is(ctx, .Regatta_Acceptance) }
has_repeat_westbound :: proc(ctx: ^dialogue.Context) -> bool { return delivery_is(ctx, .Repeat_Westbound) }
has_first_letter :: proc(ctx: ^dialogue.Context) -> bool { return delivery_is(ctx, .First_Letter) }
has_regatta_invitation :: proc(ctx: ^dialogue.Context) -> bool { return delivery_is(ctx, .Regatta_Invitation) }
has_repeat_eastbound :: proc(ctx: ^dialogue.Context) -> bool { return delivery_is(ctx, .Repeat_Eastbound) }
has_post_for_toma :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.delivery.active && state.delivery.to == .Toma
}
has_post_for_lena :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.delivery.active && state.delivery.to == .Lena
}

can_begin_first_letter :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .Unintroduced && can_begin_niko_delivery(ctx)
}

can_begin_regatta_invitation :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .Corresponding && can_begin_niko_delivery(ctx)
}

can_begin_repeat_eastbound :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && !state.delivery.active && state.repeat_deliveries % 2 == 0
}

can_begin_first_reply :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .First_Letter && can_begin_iva_delivery(ctx)
}

can_begin_regatta_acceptance :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .Invitation && can_begin_iva_delivery(ctx)
}

can_begin_repeat_westbound :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && !state.delivery.active && state.repeat_deliveries % 2 == 1
}

can_hold_meeting :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .Meeting && !state.delivery.active
}

can_report_crash :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    if state == nil || state.repair != .Not_Seen || !ensure_quest_progress(state) do return false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)
    return quest.status(&state.quest, &catalog.definition, quest_node_id(.Crash_Reported)) == .Available
}

can_inspect_crash :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.repair == .Crash_Reported
}

can_patch_wing :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.repair == .Diagnosed && state.has_wing_patch
}

can_verify_repair :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.repair == .Patched
}

resident_has_action :: proc(state: ^State, resident: Resident) -> bool {
    if state == nil do return false
    ctx := dialogue.Context {
        data = rawptr(state),
    }
    switch resident {
    case .Marta:
        return state.airfield_errand == .Not_Offered || state.airfield_errand == .Eastbound
    case .Gerta:
        return state.airfield_errand == .Westbound
    case .Niko:
        return can_complete_niko_delivery(&ctx) || can_begin_niko_delivery(&ctx) || can_hold_meeting(&ctx)
    case .Iva:
        if state.romance == .Meeting do return false
        return can_complete_iva_delivery(&ctx) || can_begin_iva_delivery(&ctx)
    case .Bojan:
        return can_report_crash(&ctx) || can_inspect_crash(&ctx) || can_patch_wing(&ctx) || can_verify_repair(&ctx)
    case .Zora:
        return true
    case .Vesna, .Petar, .Anica:
        return true
    case .Toma:
        return has_post_for_toma(&ctx) || can_begin_repeat_eastbound(&ctx)
    case .Lena:
        return has_post_for_lena(&ctx) || can_begin_repeat_westbound(&ctx)
    }
    return false
}

resident_action_signature :: proc(state: ^State, resident: Resident) -> u64 {
    if state == nil do return 0
    // FNV-1a over the campaign state which can change actionable dialogue.
    // A newly unlocked step restores the marker even when it belongs to the
    // same resident as the step just acknowledged.
    signature := u64(14695981039346656037)
    values := [10]u64 {
        u64(resident) + 1,
        u64(state.romance) + 1,
        u64(state.repair) + 1,
        u64(state.airfield_errand) + 1,
        u64(state.delivery.kind) + 1,
        u64(state.delivery.from) + 1,
        u64(state.delivery.to) + 1,
        state.delivery.active ? 2 : 1,
        u64(state.repeat_deliveries) + 1,
        u64(tarot_moment(state)) + 1,
    }
    for value in values {
        signature = (signature ~ value) * 1099511628211
    }
    return signature
}

resident_has_unseen_action :: proc(state: ^State, resident: Resident) -> bool {
    return(
        state != nil &&
        resident_has_action(state, resident) &&
        state.resident_action_seen[resident] != resident_action_signature(state, resident) \
    )
}

acknowledge_resident_action :: proc(state: ^State, resident: Resident) {
    if state == nil || !resident_has_action(state, resident) do return
    state.resident_action_seen[resident] = resident_action_signature(state, resident)
}

Catalog :: struct {
    niko_root_choices:      [6]dialogue.Choice,
    niko_reaction_choices:  [2]dialogue.Choice,
    niko_warm_choices:      [1]dialogue.Choice,
    niko_discreet_choices:  [1]dialogue.Choice,
    meeting_choices:        [2]dialogue.Choice,
    meeting_finish_choices: [1]dialogue.Choice,
    iva_root_choices:       [5]dialogue.Choice,
    iva_reaction_choices:   [2]dialogue.Choice,
    iva_warm_choices:       [1]dialogue.Choice,
    iva_discreet_choices:   [1]dialogue.Choice,
    bojan_choices:          [5]dialogue.Choice,
    zora_choices:           [4]dialogue.Choice,
    zora_return_choices:    [1]dialogue.Choice,
    vesna_choices:          [1]dialogue.Choice,
    petar_choices:          [1]dialogue.Choice,
    anica_choices:          [1]dialogue.Choice,
    toma_choices:           [3]dialogue.Choice,
    lena_choices:           [3]dialogue.Choice,
    niko_nodes:             [7]dialogue.Node,
    iva_nodes:              [4]dialogue.Node,
    bojan_nodes:            [1]dialogue.Node,
    zora_nodes:             [2]dialogue.Node,
    vesna_nodes:            [1]dialogue.Node,
    petar_nodes:            [1]dialogue.Node,
    anica_nodes:            [1]dialogue.Node,
    toma_nodes:             [1]dialogue.Node,
    lena_nodes:             [1]dialogue.Node,
    niko:                   dialogue.Definition,
    iva:                    dialogue.Definition,
    bojan:                  dialogue.Definition,
    zora:                   dialogue.Definition,
    vesna:                  dialogue.Definition,
    petar:                  dialogue.Definition,
    anica:                  dialogue.Definition,
    toma:                   dialogue.Definition,
    lena:                   dialogue.Definition,
}

init_catalog :: proc(catalog: ^Catalog) {
    if catalog == nil do return
    catalog^ = {}

    catalog.niko_root_choices = {
        dialogue.choice("Give Niko Iva's reply.", 1, has_first_reply, complete_niko_delivery),
        dialogue.choice("Give Niko Iva's regatta acceptance.", 1, has_regatta_acceptance, complete_niko_delivery),
        dialogue.choice(
            "I'll carry your sealed letter to Iva.",
            condition = can_begin_first_letter,
            effect = accept_delivery,
        ),
        dialogue.choice(
            "I'll carry your regatta invitation to Iva.",
            condition = can_begin_regatta_invitation,
            effect = accept_delivery,
        ),
        dialogue.choice("Stay under the awning.", 4, can_hold_meeting),
        dialogue.choice("I'll leave you to your work."),
    }
    catalog.niko_reaction_choices = {
        dialogue.choice("You could try to look a little less pleased.", 2),
        dialogue.choice("The letter stayed sealed.", 3),
    }
    catalog.niko_warm_choices[0] = dialogue.choice("Safe crossing, Niko.")
    catalog.niko_discreet_choices[0] = dialogue.choice("Not a word from me.")
    catalog.meeting_choices = {
        dialogue.choice("The awning suits you both.", 5),
        dialogue.choice("I saw only an ordinary arrival.", 6),
    }
    catalog.meeting_finish_choices[0] = dialogue.choice("Enjoy the regatta.", effect = finish_meeting)
    catalog.niko_nodes = {
        dialogue.node("niko", niko_text, catalog.niko_root_choices[:], niko_speaker),
        dialogue.node("niko-reaction", niko_delivery_reaction, catalog.niko_reaction_choices[:], niko_speaker),
        dialogue.node("niko-warm", niko_warm_close, catalog.niko_warm_choices[:], niko_speaker),
        dialogue.node("niko-discreet", niko_discreet_close, catalog.niko_discreet_choices[:], niko_speaker),
        dialogue.node("meeting-iva", meeting_iva_text, catalog.meeting_choices[:], iva_speaker),
        dialogue.node("meeting-niko", meeting_niko_warm, catalog.meeting_finish_choices[:], niko_speaker),
        dialogue.node("meeting-niko-discreet", meeting_niko_discreet, catalog.meeting_finish_choices[:], niko_speaker),
    }
    catalog.niko = {
        id    = "niko",
        nodes = catalog.niko_nodes[:],
    }

    catalog.iva_root_choices = {
        dialogue.choice("Give Iva Niko's sealed letter.", 1, has_first_letter, complete_iva_delivery),
        dialogue.choice("Give Iva Niko's regatta invitation.", 1, has_regatta_invitation, complete_iva_delivery),
        dialogue.choice("I'll carry your reply to Niko.", condition = can_begin_first_reply, effect = accept_delivery),
        dialogue.choice(
            "I'll carry your regatta acceptance to Niko.",
            condition = can_begin_regatta_acceptance,
            effect = accept_delivery,
        ),
        dialogue.choice("I'll leave you to tend the lamp."),
    }
    catalog.iva_reaction_choices = {
        dialogue.choice("The lamp seems especially cheerful.", 2),
        dialogue.choice("The letter stayed sealed.", 3),
    }
    catalog.iva_warm_choices[0] = dialogue.choice("Keep the light burning, Iva.")
    catalog.iva_discreet_choices[0] = dialogue.choice("Not a word from me.")
    catalog.iva_nodes = {
        dialogue.node("iva", iva_text, catalog.iva_root_choices[:], iva_speaker),
        dialogue.node("iva-reaction", iva_delivery_reaction, catalog.iva_reaction_choices[:], iva_speaker),
        dialogue.node("iva-warm", iva_warm_close, catalog.iva_warm_choices[:], iva_speaker),
        dialogue.node("iva-discreet", iva_discreet_close, catalog.iva_discreet_choices[:], iva_speaker),
    }
    catalog.iva = {
        id    = "iva",
        nodes = catalog.iva_nodes[:],
    }

    catalog.bojan_choices = {
        dialogue.choice("I saw the whole thing.", condition = can_report_crash, effect = note_crash),
        dialogue.choice("Let's inspect the wing.", condition = can_inspect_crash, effect = inspect_crash),
        dialogue.choice("Apply the canvas patch.", condition = can_patch_wing, effect = patch_wing),
        dialogue.choice("Turn the propeller.", condition = can_verify_repair, effect = confirm_repair),
        dialogue.choice("I'll leave you to it."),
    }
    catalog.bojan_nodes[0] = dialogue.node("bojan", bojan_text, catalog.bojan_choices[:], bojan_speaker)
    catalog.bojan = {
        id    = "bojan",
        nodes = catalog.bojan_nodes[:],
    }

    catalog.zora_choices = {
        dialogue.choice("Just tell me which way the wind is blowing today.", 1, can_deal_tarot, deal_single),
        dialogue.choice("Where I came from, where I am, and where I might go.", 1, can_deal_tarot, deal_three),
        dialogue.choice("I have time. Lay out the full cross.", 1, can_deal_tarot, deal_cross),
        dialogue.choice("Another time, grazie."),
    }
    catalog.zora_return_choices[0] = dialogue.choice("Enough cards. I'll watch the real sky.")
    catalog.zora_nodes = {
        dialogue.node("zora", zora_text, catalog.zora_choices[:], zora_speaker),
        dialogue.node("zora-reading", zora_reading_text, catalog.zora_return_choices[:], zora_speaker),
    }
    catalog.zora = {
        id    = "zora",
        nodes = catalog.zora_nodes[:],
    }

    catalog.vesna_choices[0] = dialogue.choice("Thanks, doctor. I'll take it slower.")
    catalog.vesna_nodes[0] = dialogue.node("vesna", vesna_text, catalog.vesna_choices[:], vesna_speaker)
    catalog.vesna = {
        id    = "vesna",
        nodes = catalog.vesna_nodes[:],
    }

    catalog.petar_choices[0] = dialogue.choice("I'll try to return by the door next time.")
    catalog.petar_nodes[0] = dialogue.node("petar", petar_text, catalog.petar_choices[:], petar_speaker)
    catalog.petar = {
        id    = "petar",
        nodes = catalog.petar_nodes[:],
    }

    catalog.anica_choices[0] = dialogue.choice("Water first. Understood.")
    catalog.anica_nodes[0] = dialogue.node("anica", anica_text, catalog.anica_choices[:], anica_speaker)
    catalog.anica = {
        id    = "anica",
        nodes = catalog.anica_nodes[:],
    }

    catalog.toma_choices = {
        dialogue.choice("Give Toma the east-island post.", condition = has_post_for_toma, effect = complete_toma_delivery),
        dialogue.choice("I'll carry the island post to Lena.", condition = can_begin_repeat_eastbound, effect = accept_post_delivery),
        dialogue.choice("I'll come back when the postbag is ready."),
    }
    catalog.toma_nodes[0] = dialogue.node(
        "toma",
        proc(_: ^dialogue.Context) -> string { return "West island post. Every crossing counts, even when the bag is light." },
        catalog.toma_choices[:],
        proc(_: ^dialogue.Context) -> string { return "TOMA · POSTMASTER" },
    )
    catalog.toma = {id = "toma", nodes = catalog.toma_nodes[:]}

    catalog.lena_choices = {
        dialogue.choice("Give Lena the west-island post.", condition = has_post_for_lena, effect = complete_lena_delivery),
        dialogue.choice("I'll carry the island post to Toma.", condition = can_begin_repeat_westbound, effect = accept_post_delivery),
        dialogue.choice("I'll let you finish sorting."),
    }
    catalog.lena_nodes[0] = dialogue.node(
        "lena",
        proc(_: ^dialogue.Context) -> string { return "East island post. Letters above, lamp glass below, bread where I can see it." },
        catalog.lena_choices[:],
        proc(_: ^dialogue.Context) -> string { return "LENA · POSTMASTER" },
    )
    catalog.lena = {id = "lena", nodes = catalog.lena_nodes[:]}
}
