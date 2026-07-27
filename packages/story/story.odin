package story

import dialogue "../dialogue"
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
    romance:              Romance_Stage,
    repair:               Repair_Stage,
    delivery:             Delivery,
    completed_deliveries: int,
    repeat_deliveries:    int,
    stamps_earned:        int,
    has_wing_patch:       bool,
    tarot_readings:       int,
    tarot_seed:           u32,
    tarot_last_moment:    u32,
    tarot_layout:         tarot.Layout,
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
    }
    return ""
}

resident_island :: proc(resident: Resident) -> Island {
    switch resident {
    case .Marta, .Iva:
        return .East
    case .Gerta, .Niko, .Bojan:
        return .West
    case .Zora:
        return .East
    }
    return .West
}

begin_delivery :: proc(state: ^State) -> bool {
    if state == nil || state.delivery.active do return false

    delivery: Delivery
    switch state.romance {
    case .Unintroduced:
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
        eastbound := state.repeat_deliveries % 2 == 0
        if eastbound {
            delivery = {
                active      = true,
                kind        = .Repeat_Eastbound,
                from        = .Niko,
                to          = .Iva,
                origin      = .West,
                destination = .East,
                subject     = "Bread, postcards, and one pressed flower",
            }
        } else {
            delivery = {
                active      = true,
                kind        = .Repeat_Westbound,
                from        = .Iva,
                to          = .Niko,
                origin      = .East,
                destination = .West,
                subject     = "Lamp glass and a note for supper",
            }
        }
    }
    state.delivery = delivery
    return true
}

complete_delivery :: proc(state: ^State, recipient: Resident) -> bool {
    if state == nil || !state.delivery.active || state.delivery.to != recipient do return false

    switch state.delivery.kind {
    case .First_Letter:
        if state.romance != .Unintroduced do return false
        state.romance = .First_Letter
    case .First_Reply:
        if state.romance != .First_Letter do return false
        state.romance = .Corresponding
    case .Regatta_Invitation:
        if state.romance != .Corresponding do return false
        state.romance = .Invitation
    case .Regatta_Acceptance:
        if state.romance != .Invitation || state.repair != .Repaired do return false
        state.romance = .Meeting
    case .Repeat_Eastbound, .Repeat_Westbound:
        if state.romance != .Together do return false
        state.repeat_deliveries += 1
    case .None:
        return false
    }

    state.delivery.active = false
    state.completed_deliveries += 1
    state.stamps_earned += 1
    return true
}

complete_meeting :: proc(state: ^State) -> bool {
    if state == nil || state.romance != .Meeting || state.delivery.active do return false
    state.romance = .Together
    return true
}

report_crash :: proc(state: ^State) -> bool {
    if state == nil || state.repair != .Not_Seen do return false
    state.repair = .Crash_Reported
    return true
}

diagnose_crash :: proc(state: ^State) -> bool {
    if state == nil || state.repair != .Crash_Reported do return false
    state.repair = .Diagnosed
    state.has_wing_patch = true
    return true
}

apply_wing_patch :: proc(state: ^State) -> bool {
    if state == nil || state.repair != .Diagnosed || !state.has_wing_patch do return false
    state.has_wing_patch = false
    state.repair = .Patched
    return true
}

verify_repair :: proc(state: ^State) -> bool {
    if state == nil || state.repair != .Patched do return false
    state.repair = .Repaired
    return true
}

state_from_context :: proc(ctx: ^dialogue.Context) -> ^State {
    if ctx == nil || ctx.data == nil do return nil
    return cast(^State)ctx.data
}

niko_speaker :: proc(_: ^dialogue.Context) -> string { return "NIKO" }
iva_speaker :: proc(_: ^dialogue.Context) -> string { return "IVA" }
bojan_speaker :: proc(_: ^dialogue.Context) -> string { return "BOJAN" }
zora_speaker :: proc(_: ^dialogue.Context) -> string { return "ZORA" }

zora_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.tarot_readings == 0 {
        return(
            "Chiudi la persiana, piccolo corriere. La bura mescola già abbastanza. Le carte non comandano il mare; elles montrent dove tira il vento." \
        )
    }
    if state.tarot_last_moment == tarot_moment(state) {
        return "Le carte hanno parlé per questo vento. Ora guarda il cielo vero; ritorna quando qualcosa cambia."
    }
    return "Siedi. Il vento ha girato depuis l'ultima volta; vediamo se les cartes se ne sono accorte."
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
        return "due persone devono scegliere la stessa traversée"
    case id == 7:
        return "il viaggio vuole mani ferme, non fretta"
    case id == 9:
        return "una lampe solitaria può ancora guidare qualcuno"
    case id == 10:
        return "la ruota gira, mais seulement si qualcuno la spinge"
    case id == 16:
        return "ciò che sembra una rovina demande prima un'ispezione"
    case id == 17:
        return "una luce lontana è aussi una promessa"
    case id == 18:
        return "il meteo nasconde metà della route"
    case id == 19:
        return "la chiarezza arriverà con il giorno"
    case id >= 22 && id < 36:
        return "il lavoro e il coraggio tirano nella stessa direzione"
    case id >= 36 && id < 50:
        return "gli affetti viaggiano meglio in un recipiente semplice"
    case id >= 50 && id < 64:
        return "una parola taglia; una parola precisa ripara"
    case id >= 64:
        return "la cosa concreta sotto la mano mérite confiance"
    }
    return "il cambiamento è già entrato dalla finestra"
}

zora_story_omen :: proc(state: ^State) -> string {
    if state == nil do return "Non correre dietro al simbolo; guarda cosa fa muovere."
    switch state.romance {
    case .Unintroduced:
        return "Due persone tengono le stesse ore su rive diverse. Non la chiamano ancora attesa."
    case .First_Letter:
        return "Una cosa sigillata attraversa meglio il mare in mani che savent se taire."
    case .Corresponding:
        return "Le distanze diventano piccole prima sulla carta, poi sotto i piedi."
    case .Invitation:
        if state.repair != .Repaired {
            return "Tela, vento, e un viaggio da réparer prima di essere promesso."
        }
        return "La strada nel cielo è pronta. Il coraggio deve seulement salire a bordo."
    case .Meeting:
        return "Due sedie sotto una tenda blu fanno moins ombra di una sedia vuota."
    case .Together:
        return "Tu connais la route: pane all'andata, vetro ben avvolto al ritorno."
    }
    return ""
}

zora_reading_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.tarot_layout.count == 0 do return "Il tavolo è vuoto; qualcosa ha mangiato la sorte."
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
            "Passato: %s. Ora: %s.\nPossibile: %s. %s",
            tarot.card_name(first.card),
            tarot.card_name(second.card),
            tarot.card_name(third.card),
            zora_story_omen(state),
        )
    case .Celtic_Cross:
        crossing := state.tarot_layout.placements[1]
        shore := state.tarot_layout.placements[state.tarot_layout.count - 1]
        return fmt.tprintf(
            "Cuore: %s. Contro: %s.\nRiva lontana: %s. %s",
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
    if state == nil do return "Buongiorno. Die forni seront warm avant che il porto se réveille."
    if state.delivery.active && state.delivery.to == .Niko {
        switch state.delivery.kind {
        case .First_Reply:
            return "Ah, du bist back preko il mare. Hat Iva una risposta envoyé?"
        case .Regatta_Acceptance:
            return "Le moteur de Bojan cruzó la baia à l'alba. Ist das la parola d'Iva?"
        case .Repeat_Westbound:
            return "Le verre de lampe voyage malissimo. Hoffentlich Iva lo ha packed mejor que moi."
        case .None, .First_Letter, .Regatta_Invitation, .Repeat_Eastbound:
        }
    }
    switch state.romance {
    case .Unintroduced:
        return "La lampe de l'isola est clignote twice avant alba. Iva veglia quando mes forni aussi."
    case .First_Letter:
        return "La boîte de cardamomo looks molto sospetta quand uno wartet auf risposta."
    case .Corresponding:
        return "La regatta braucht un boulanger, certo. Io preferirebbe aussi una gardienne du phare."
    case .Invitation:
        return "Hay una tenda blu am Quai. Nobody sait pourquoi io la regarde toujours."
    case .Meeting:
        return "Iva ha trouvé la tenda blu. Sie scheint kleiner con due persone dessous."
    case .Together:
        return "Iva dit que le verre può aspettare. Das pane offenbar nicht."
    }
    return ""
}

niko_delivery_reaction :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return ""
    switch state.delivery.kind {
    case .First_Reply:
        return "She ricordava la farina sur ma première nota. No era la parte que esperaba."
    case .Regatta_Acceptance:
        return "Elle viene. Ich muss la tenda aussehen lassen comme si non l'avessi lucidée."
    case .Repeat_Westbound:
        return "Le verre ha survécu, et elle incluyó instrukcije za cena. Uno di loro ist plus fragile."
    case .None, .First_Letter, .Regatta_Invitation, .Repeat_Eastbound:
        return "Grazie. Certaines cose arrivent meglio wenn niemand le abre en route."
    }
    return ""
}

niko_warm_close :: proc(_: ^dialogue.Context) -> string {
    return "Va bene. Ich stelle noch un plateau dentro; attendre va meglio con lavoro utile."
}

niko_discreet_close :: proc(_: ^dialogue.Context) -> string {
    return "Bene. Una lettre sigillata mérite almeno una persona qui sait schweigen."
}

meeting_iva_text :: proc(_: ^dialogue.Context) -> string {
    return "Bojan appelle le vol routine. But routine Landungen benutzen toutes les roues, sì?"
}

meeting_niko_warm :: proc(_: ^dialogue.Context) -> string {
    return "Bleib pour la première course. Ho fatto troppo pane mit remarquable foresight."
}

meeting_niko_discreet :: proc(_: ^dialogue.Context) -> string {
    return "Ti dobbiamo una traversée tranquille sans Fragen. Auch cena, si le mare te donne faim."
}

iva_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Dobro jutro. La lampe ist prête; el meteo todavía ne sait pas."
    if state.delivery.active && state.delivery.to == .Iva {
        switch state.delivery.kind {
        case .First_Letter:
            return "Una lettre attraversò tutto quel mare bleu pour trouver ce phare."
        case .Regatta_Invitation:
            return "L'écriture de Niko devient gerader quand il prétend no estar nervioso."
        case .Repeat_Eastbound:
            return "Quel pacco riecht comme si Niko confundiera la route postale con una despensa."
        case .None, .First_Reply, .Regatta_Acceptance, .Repeat_Westbound:
        }
    }
    switch state.romance {
    case .Unintroduced:
        return "Due lampi signifient acqua chiara. Uno sah immer ein bisschen solo."
    case .First_Letter:
        return "Er ricordava il cardamomo. Bene, le phare peut offrir une feuille de carta."
    case .Corresponding:
        return "La posta dell'isola west ist devenue remarquablement puntual."
    case .Invitation:
        if state.repair == .Repaired {
            return "Tu reparaste l'aereo de Bojan before che io lo necesitara. Grazie; jetzt posso rispondere."
        }
        return "Posso répondre à Niko, but l'ala rotta non peut me porter. Nema regatta todavía."
    case .Meeting:
        return "L'isola west ist plus bruyante que le phare. Niko, heureusement, no."
    case .Together:
        return "Niko manda pane comme si el mare fosse un problema que man durch füttern résout."
    }
    return ""
}

iva_delivery_reaction :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return ""
    switch state.delivery.kind {
    case .First_Letter:
        return "Er ricordava il cardamomo. Dite à Niko: due lampi, porque uno se sentiva solo."
    case .Regatta_Invitation:
        if state.repair == .Repaired {
            return "L'aereo de Bojan ist pronto. Grazie; ta gentillesse d'avant ha organisé ma réponse."
        }
        return "Io iría, mais l'aereo de Bojan montre plus de cielo durch l'ala que sopra."
    case .Repeat_Eastbound:
        return "Pane, cartes postales und un fiore. Ha emballé drei sortes de meteo."
    case .None, .First_Reply, .Regatta_Acceptance, .Repeat_Westbound:
        return "Encore sigillata. Grazie por traiter la traversée comme parte della promessa."
    }
    return ""
}

iva_warm_close :: proc(_: ^dialogue.Context) -> string {
    return "Non sourire ainsi al faro. Das ermutigt les mouettes."
}

iva_discreet_close :: proc(_: ^dialogue.Context) -> string {
    return "Grazie. Le isole sind déjà petites sans que les lettres deviennent strade pubbliche."
}

bojan_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "L'aeroplano und ich faisons repos. Alles tranquillo, más o menos."
    switch state.repair {
    case .Not_Seen:
        return "L'atterraggio war perfekt. Le ground est arrivé trop tôt. Hai visto niente plus compliqué."
    case .Crash_Reported:
        return "Maintenant la versione officielle ist breve, possiamo inspecter l'ala honnêtement."
    case .Diagnosed:
        return "Uno panneau di tela déchiré. Ich habe un patch; tu as mani plus stabili que ma réputation."
    case .Patched:
        return "Patch tendu, Rippen gerade, controles libres. Voilà: una vuelta prudente dell'elica."
    case .Repaired:
        if state.romance == .Invitation {
            return "L'aereo ist pronto pour Iva. Ho même nettoyé el asiento qui non m'appartient."
        }
        return "Patch tendu, Rippen gerade, controles libres. Basta—das nennen wir ingénierie."
    }
    return ""
}

accept_delivery :: proc(ctx: ^dialogue.Context) { _ = begin_delivery(state_from_context(ctx)) }
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
    return(
        state.romance == .Unintroduced ||
        state.romance == .Corresponding ||
        (state.romance == .Together && state.repeat_deliveries % 2 == 0) \
    )
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

can_hold_meeting :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .Meeting && !state.delivery.active
}

can_report_crash :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.repair == .Not_Seen
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
    case .Marta, .Gerta:
        return true
    case .Niko:
        return can_complete_niko_delivery(&ctx) || can_begin_niko_delivery(&ctx) || can_hold_meeting(&ctx)
    case .Iva:
        if state.romance == .Meeting do return false
        return can_complete_iva_delivery(&ctx) || can_begin_iva_delivery(&ctx)
    case .Bojan:
        return can_report_crash(&ctx) || can_inspect_crash(&ctx) || can_patch_wing(&ctx) || can_verify_repair(&ctx)
    case .Zora:
        return true
    }
    return false
}

Catalog :: struct {
    niko_root_choices:      [4]dialogue.Choice,
    niko_reaction_choices:  [2]dialogue.Choice,
    niko_warm_choices:      [1]dialogue.Choice,
    niko_discreet_choices:  [1]dialogue.Choice,
    meeting_choices:        [2]dialogue.Choice,
    meeting_finish_choices: [1]dialogue.Choice,
    iva_root_choices:       [3]dialogue.Choice,
    iva_reaction_choices:   [2]dialogue.Choice,
    iva_warm_choices:       [1]dialogue.Choice,
    iva_discreet_choices:   [1]dialogue.Choice,
    bojan_choices:          [5]dialogue.Choice,
    zora_choices:           [4]dialogue.Choice,
    zora_return_choices:    [1]dialogue.Choice,
    niko_nodes:             [7]dialogue.Node,
    iva_nodes:              [4]dialogue.Node,
    bojan_nodes:            [1]dialogue.Node,
    zora_nodes:             [2]dialogue.Node,
    niko:                   dialogue.Definition,
    iva:                    dialogue.Definition,
    bojan:                  dialogue.Definition,
    zora:                   dialogue.Definition,
}

init_catalog :: proc(catalog: ^Catalog) {
    if catalog == nil do return
    catalog^ = {}

    catalog.niko_root_choices = {
        dialogue.choice("Dai a Niko la lettre sigillata.", 1, can_complete_niko_delivery, complete_niko_delivery),
        dialogue.choice("Yes, porto-la preko il mare.", condition = can_begin_niko_delivery, effect = accept_delivery),
        dialogue.choice("Restez sous la tenda.", 4, can_hold_meeting),
        dialogue.choice("Ti lascio à your lavoro."),
    }
    catalog.niko_reaction_choices = {
        dialogue.choice("Potresti essayer de sembler weniger content.", 2),
        dialogue.choice("La lettre stayed sigillata.", 3),
    }
    catalog.niko_warm_choices[0] = dialogue.choice("Buona traversée, Niko.")
    catalog.niko_discreet_choices[0] = dialogue.choice("Pas una parola de moi.")
    catalog.meeting_choices = {
        dialogue.choice("La tenda vous va bene à tous deux.", 5),
        dialogue.choice("Ho visto seulement un'arrivée routine.", 6),
    }
    catalog.meeting_finish_choices[0] = dialogue.choice("Genießt la regatta.", effect = finish_meeting)
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
        dialogue.choice("Dai a Iva la lettre sigillata.", 1, can_complete_iva_delivery, complete_iva_delivery),
        dialogue.choice("I'll porter ta risposta.", condition = can_begin_iva_delivery, effect = accept_delivery),
        dialogue.choice("Ti lascio tend the lampe."),
    }
    catalog.iva_reaction_choices = {
        dialogue.choice("La lampe semble vraiment allegra.", 2),
        dialogue.choice("La lettre stayed sigillata.", 3),
    }
    catalog.iva_warm_choices[0] = dialogue.choice("Buona lumière, Iva.")
    catalog.iva_discreet_choices[0] = dialogue.choice("Pas una parola de moi.")
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
        dialogue.choice("Ho visto toute la chose.", condition = can_report_crash, effect = note_crash),
        dialogue.choice("Let's inspect die ala.", condition = can_inspect_crash, effect = inspect_crash),
        dialogue.choice("Place le patch de tela.", condition = can_patch_wing, effect = patch_wing),
        dialogue.choice("Turn die propeller.", condition = can_verify_repair, effect = confirm_repair),
        dialogue.choice("Je te laisse continuar."),
    }
    catalog.bojan_nodes[0] = dialogue.node("bojan", bojan_text, catalog.bojan_choices[:], bojan_speaker)
    catalog.bojan = {
        id    = "bojan",
        nodes = catalog.bojan_nodes[:],
    }

    catalog.zora_choices = {
        dialogue.choice("Dimmi soltanto che vento tira oggi.", 1, can_deal_tarot, deal_single),
        dialogue.choice("Da dove vengo, dove sono, dove potrei andare.", 1, can_deal_tarot, deal_three),
        dialogue.choice("Ho tempo. Stendi tutta la croce.", 1, can_deal_tarot, deal_cross),
        dialogue.choice("Un'altra volta, grazie."),
    }
    catalog.zora_return_choices[0] = dialogue.choice("Basta carte. Guardo il cielo vero.")
    catalog.zora_nodes = {
        dialogue.node("zora", zora_text, catalog.zora_choices[:], zora_speaker),
        dialogue.node("zora-reading", zora_reading_text, catalog.zora_return_choices[:], zora_speaker),
    }
    catalog.zora = {
        id    = "zora",
        nodes = catalog.zora_nodes[:],
    }
}
