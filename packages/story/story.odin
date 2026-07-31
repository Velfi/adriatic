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
    Mirna,
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
    Clinic_Medicine,
    Clinic_Linens,
    Clinic_Water,
}

Cargo_Care :: enum {
    Unchosen,
    Orderly,
    Expressive,
}

Delivery :: struct {
    active:      bool,
    kind:        Delivery_Kind,
    from, to:    Resident,
    origin:      Island,
    destination: Island,
    subject:     string,
    care:        Cargo_Care,
}

State :: struct {
    quest:                        quest.State,
    romance:                      Romance_Stage,
    repair:                       Repair_Stage,
    airfield_errand:              Airfield_Errand_Stage,
    delivery:                     Delivery,
    completed_deliveries:         int,
    repeat_deliveries:            int,
    stamps_earned:                int,
    bonus_stamps:                 int,
    careful_deliveries:           int,
    expressive_deliveries:        int,
    friendship_points:            int,
    magneto_wrapped:              bool,
    weather_reading_done:         bool,
    medicine_delivered:           bool,
    linens_delivered:             bool,
    water_delivered:              bool,
    has_weather_briefing:         bool,
    has_clinic_satchel:           bool,
    has_dry_wrap:                 bool,
    has_recovery_kit:             bool,
    has_wing_patch:               bool,
    tarot_readings:               int,
    tarot_seed:                   u32,
    tarot_last_moment:            u32,
    tarot_layout:                 tarot.Layout,
    clinic_visits:                int,
    last_clinic_visit_was_tumble: bool,
    // Quest punctuation is a notification, not a permanent label. Remember
    // the action state last seen in conversation so it stays gone until that
    // resident has something new to say or do.
    resident_action_seen:         [Resident]u64,
}

award_friendship :: proc(state: ^State, points: int) -> bool {
    if state == nil || points <= 0 || state.friendship_points > max(int) - points do return false
    state.friendship_points += points
    return true
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
    case .Mirna:
        return "Dr Mirna"
    }
    return ""
}

resident_from_speaker :: proc(speaker: string) -> (Resident, bool) {
    switch speaker {
    case "MARTA":
        return .Marta, true
    case "GERTA":
        return .Gerta, true
    case "NIKO":
        return .Niko, true
    case "IVA":
        return .Iva, true
    case "BOJAN":
        return .Bojan, true
    case "ZORA":
        return .Zora, true
    case "DR VESNA":
        return .Vesna, true
    case "PETAR":
        return .Petar, true
    case "ANICA":
        return .Anica, true
    case "TOMA · POSTMASTER":
        return .Toma, true
    case "LENA · POSTMASTER":
        return .Lena, true
    case "DR MIRNA":
        return .Mirna, true
    }
    return {}, false
}

resident_island :: proc(resident: Resident) -> Island {
    switch resident {
    case .Marta, .Iva, .Lena, .Mirna:
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
    state.delivery =
        eastbound ? Delivery{active = true, kind = .Repeat_Eastbound, from = .Toma, to = .Lena, origin = .West, destination = .East, subject = "Bread, postcards, and one pressed flower"} : Delivery{active = true, kind = .Repeat_Westbound, from = .Lena, to = .Toma, origin = .East, destination = .West, subject = "Lamp glass and a note for supper"}
    return true
}

begin_local_delivery :: proc(state: ^State, kind: Delivery_Kind) -> bool {
    if state == nil || state.delivery.active || !ensure_quest_progress(state) do return false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)

    node: Quest_Node
    delivery: Delivery
    #partial switch kind {
    case .Clinic_Medicine:
        node = .Clinic_Medicine
        delivery = {
            active      = true,
            kind        = kind,
            from        = .Vesna,
            to          = .Anica,
            origin      = .West,
            destination = .East,
            subject     = "Dr Vesna's clinic medicine",
        }
    case .Clinic_Linens:
        node = .Clinic_Linens
        delivery = {
            active      = true,
            kind        = kind,
            from        = .Petar,
            to          = .Anica,
            origin      = .West,
            destination = .East,
            subject     = "Petar's dry clinic linens",
        }
    case .Clinic_Water:
        node = .Clinic_Water
        delivery = {
            active      = true,
            kind        = kind,
            from        = .Anica,
            to          = .Vesna,
            origin      = .East,
            destination = .West,
            subject     = "Anica's sealed drinking water",
        }
    case:
        return false
    }
    if !quest.accept(&state.quest, &catalog.definition, quest_node_id(node)) do return false
    state.delivery = delivery
    return true
}

accept_weather_reading :: proc(state: ^State) -> bool {
    if state == nil || !ensure_quest_progress(state) do return false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)
    return quest.accept(&state.quest, &catalog.definition, quest_node_id(.Weather_Reading))
}

complete_weather_reading :: proc(state: ^State) -> bool {
    if state == nil do return false
    update, published := publish_quest_event(state, {kind = .Inspect, key = "weather-reading"})
    return published && update.completed_count > 0
}

choose_cargo_care :: proc(state: ^State, care: Cargo_Care) -> bool {
    if state == nil || !state.delivery.active || care == .Unchosen do return false
    state.delivery.care = care
    return true
}

choose_orderly_cargo :: proc(ctx: ^dialogue.Context) {
    _ = choose_cargo_care(state_from_context(ctx), .Orderly)
}

choose_expressive_cargo :: proc(ctx: ^dialogue.Context) {
    _ = choose_cargo_care(state_from_context(ctx), .Expressive)
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
    case .Clinic_Medicine:
        event = {
            kind   = .Deliver,
            key    = "clinic-medicine",
            target = "anica",
        }
    case .Clinic_Linens:
        event = {
            kind   = .Deliver,
            key    = "clinic-linens",
            target = "anica",
        }
    case .Clinic_Water:
        event = {
            kind   = .Deliver,
            key    = "clinic-water",
            target = "vesna",
        }
    case .None:
        return false
    }
    update, published := publish_quest_event(state, event)
    if !published || update.completed_count == 0 do return false
    _ = award_friendship(state, 1)

    if state.delivery.care == .Orderly {
        state.careful_deliveries += 1
        // Every third demonstrably careful crossing earns a postal merit
        // stamp in addition to the ordinary completion stamp.
        if state.careful_deliveries % 3 == 0 {
            state.bonus_stamps += 1
            state.stamps_earned += 1
        }
    } else if state.delivery.care == .Expressive {
        state.expressive_deliveries += 1
    }
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
    // Marta supplies and wraps the oilcloth during acceptance. Keeping this
    // explicit lets later cargo-condition systems inspect the protection.
    state.magneto_wrapped = true
    return true
}

wrap_broken_magneto :: proc(state: ^State) -> bool {
    if state == nil || state.airfield_errand != .Westbound do return false
    state.magneto_wrapped = true
    return true
}

handoff_broken_magneto :: proc(state: ^State) -> bool {
    if state == nil || state.airfield_errand != .Westbound || !state.magneto_wrapped do return false
    update, published := publish_quest_event(state, {kind = .Deliver, key = "broken-magneto", target = "gerta"})
    return published && update.completed_count > 0
}

return_replacement_magneto :: proc(state: ^State) -> bool {
    if state == nil || state.airfield_errand != .Eastbound do return false
    update, published := publish_quest_event(state, {kind = .Deliver, key = "replacement-magneto", target = "marta"})
    return published && update.completed_count > 0
}

magneto_memory_text :: proc(resident: Resident) -> string {
    switch resident {
    case .Marta:
        return(
            "Il replacement magneto parte avant il caffè. Gerta chiama questo prova che aveva raison; io, che il vecchio meritava pensione con onore." \
        )
    case .Gerta:
        return(
            "Marta rapporte che il replacement magneto parte al primo tiraggio. Per lei prova la maintenance; curiosamente, prova aussi la mia replacement." \
        )
    case .Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena, .Mirna:
        return ""
    }
    return ""
}

magneto_opinion_text :: proc(resident, favored_sister: Resident) -> string {
    switch resident {
    case .Marta:
        if favored_sister == .Marta {
            return(
                "Esatto. Due estati extra da un cracked magneto non sono ostinazione; sono planification prudente della pensione. Dillo a Gerta lentamente." \
            )
        }
        return(
            "Aussi vero. Gerta ha trouvé la replacement corretta avant che ammettessi il bisogno. Una sister può avere raison senza una parade." \
        )
    case .Gerta:
        if favored_sister == .Marta {
            return(
                "Correct. Marta ha sentito la crack avant ogni instrument e l'ha tenuta sicura fino alla replacement. Lo concederò in scrittura très piccola." \
            )
        }
        return(
            "Ja. Serie corretta, timing corretto, delivery asciutta. Mais se Marta domanda, dite solo che la machine ha deciso indépendamment." \
        )
    case .Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena, .Mirna:
        return ""
    }
    return ""
}

magneto_accept_careful_text :: proc() -> string {
    return(
        "Bene. Oilcloth intorno al metal, knot lontano dai terminals, und broken magneto sopra lo spray. Gerta apprécie i nomi corretti." \
    )
}

magneto_accept_inspection_text :: proc() -> string {
    return(
        "Solo corrieri con calze bagnate. Arriva asciutto, di' broken magneto avant ogni storia, et forse inspecta solo il knot." \
    )
}

magneto_handoff_crack_text :: proc() -> string {
    return(
        "Ja. Sotto olio pulito, la crack continua plus lontano di quanto confessava. Stessa serie, replacement corretta, und zero estati prestito." \
    )
}

magneto_handoff_marta_text :: proc() -> string {
    return(
        "Abbastanza lunga da provare che sentiva la machine correttamente. Marta dice maintenance; io, affection con una torque wrench." \
    )
}

magneto_return_dry_text :: proc() -> string {
    return(
        "Perfetto. Coils asciutte, terminals puliti, und zero sale. Gerta diffida dei corrieri, mais prepara il loro successo." \
    )
}

magneto_return_knot_text :: proc() -> string {
    return(
        "Naturalmente. Due giri, un square knot, et una coda abbastanza lunga per criticare. Mia sister scrive instructions anche con lo spago." \
    )
}

airfield_news_warm_text :: proc(resident: Resident) -> string {
    switch resident {
    case .Marta:
        return(
            "Piano va bene. Un faro, un forno, und persone puniscono tutti la fretta—solo il repair manual lo ammette." \
        )
    case .Gerta:
        return "Ja. Niko planifica con farina, Iva mit meteo; tra loro, una traversata diventa pratica."
    case .Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena, .Mirna:
        return ""
    }
    return ""
}

airfield_news_discreet_text :: proc(resident: Resident) -> string {
    switch resident {
    case .Marta:
        return(
            "Ogni runway, quai, und cucina ha testimoni. Fortunatamente, ciascuno è occupato a prétendre il contrario." \
        )
    case .Gerta:
        return(
            "Isole piccole, sightlines lunghe, et zero veri segreti. La privacy sopravvive perché chacun perde un fatto." \
        )
    case .Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena, .Mirna:
        return ""
    }
    return ""
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
mirna_speaker :: proc(_: ^dialogue.Context) -> string { return "DR MIRNA" }
vesna_speaker :: proc(_: ^dialogue.Context) -> string { return "DR VESNA" }
petar_speaker :: proc(_: ^dialogue.Context) -> string { return "PETAR" }
anica_speaker :: proc(_: ^dialogue.Context) -> string { return "ANICA" }

clinic_is_first_visit :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state == nil || state.clinic_visits <= 1
}

clinic_is_repeat_visit :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.clinic_visits > 1
}

vesna_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.delivery.active && state.delivery.kind == .Clinic_Water {
        return(
            "Anica's sealed water, arrivata west et ancora intatta. Dobro—una clinica può preparare prudenza avant che qualcuno ne abbia bisogno." \
        )
    }
    if state != nil && state.last_clinic_visit_was_tumble {
        return(
            "Qualcuno ti ha visto fare una bella tumble, et ti hanno portato qui. Niente rotto, dobro—but una concussion può fare sogni très strani. Repos, acqua, und dimmi se il mondo continua a inventare cose." \
        )
    }
    if state == nil || state.clinic_visits == 0 {
        return(
            "La clinica è calme, dobro. Mais teniamo un letto pronto, perché i piloti confondono fortuna mit meteo." \
        )
    }
    if state.clinic_visits == 1 {
        return "Zero bones rotte. Un poco de repos, beaucoup acqua, und oggi zero bravura. Gli occhiali sono sul tray."
    }
    switch state.clinic_visits % 3 {
    case 0:
        return fmt.tprintf(
            "Visita numero %d. Conosci la routine: acqua, repos, puis inspecta il meteo avant il motor.",
            state.clinic_visits,
        )
    case 1:
        return fmt.tprintf(
            "Visita numero %d. Il tray ha ricordato gli occhiali; preferisco quando i pazienti imparano plus vite dei mobili. Acqua, repos, meteo.",
            state.clinic_visits,
        )
    case 2:
        return fmt.tprintf(
            "Visita numero %d. Stesso pilota, nuova bruise, und occhiali familiari. Bene: acqua prima; puis compariamo la storia con il meteo.",
            state.clinic_visits,
        )
    }
    return ""
}

vesna_care_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.clinic_visits > 1 {
        return(
            "Dobro. Alla seconda visita, la sagesse costa ancora meno dei bandages. Acqua prima, meteo secondo, aeroplano ultimo." \
        )
    }
    return "Bene. Bravura è medicina costosa, und la clinica non la conserva. Acqua prima; meteo avant il motor."
}

vesna_joke_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Da sopra, forse. Da questo letto, l'atterraggio è arrivato con excellente clarté. Conserva la joke; perdi la prossima visita." \
    )
}

vesna_repeat_honest_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Alors miglioriamo una variable, non inventiamo una causa eroica. Hai controllato il meteo; après inspectiamo velocità, fuel, und giudizio." \
    )
}

vesna_repeat_memory_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Excellent: la répétition ha prodotto memoria. Ora la memoria produca cautela, così gli occhiali restano fuori dal tray." \
    )
}

petar_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.last_clinic_visit_was_tumble {
        return(
            "Qualcuno ha visto la tua tumble et ha chiamato la clinica. Se ricordi sogni completamente pazzi, blame la concussion, non le linens; loro hanno alibi puliti." \
        )
    }
    if state == nil || state.clinic_visits == 0 {
        return "Io lavo le clinic linens ogni mattina. Das non è una invitation a occupare il letto, capito?"
    }
    if state.clinic_visits == 1 {
        return(
            "Gli occhiali sono sul tray, la scarf è asciutta, und l'aeroplano aspetta all'airfield. In questo ordine." \
        )
    }
    switch state.clinic_visits % 3 {
    case 0:
        return fmt.tprintf(
            "Visita numero %d. Gli occhiali hanno trouvé il tray senza assistenza. Magari il pilota mostrasse uguale navigation.",
            state.clinic_visits,
        )
    case 1:
        return fmt.tprintf(
            "Visita numero %d. Una scarf asciutta, due sheets pulite, und zero applausi. Vesna gestisce medicine; io proteggo le linens.",
            state.clinic_visits,
        )
    case 2:
        return fmt.tprintf(
            "Visita numero %d. La scarf è asciutta, la door resta innocente, und l'aeroplano aspetta fuori. In questo ordine.",
            state.clinic_visits,
        )
    }
    return ""
}

petar_door_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "La door ha una handle, un sign, und zero propeller. Une excellente machine. Vesna raccomanda di usarla piano." \
    )
}

petar_window_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Più vicina, da. Anche chiusa. La prossima volta scegli la door avant che io scelga quale linen bagnata diventa la nuova scarf." \
    )
}

petar_repeat_door_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Alors la door conserva il record de sécurité perfetto. Informerò Vesna che un equipment della clinica è rimasto innocente." \
    )
}

petar_repeat_linens_close :: proc(_: ^dialogue.Context) -> string {
    return "Lo fanno. Questa sheet ha demandé transfer al faro. Ho negato; anche le linens devono finire il turno."
}

anica_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.delivery.active && state.delivery.kind == .Clinic_Medicine {
        return(
            "La medicine case di Vesna, enfin. Seal asciutto, labels droite, und zero mare dentro: exactement come una clinica preferisce." \
        )
    }
    if state != nil && state.delivery.active && state.delivery.kind == .Clinic_Linens {
        return(
            "Petar's dry clinic linens hanno battuto la bura. Mettili qui, avant che il vento presenti un reclamo tardivo." \
        )
    }
    if state != nil && state.last_clinic_visit_was_tumble {
        return(
            "Un vicino ti ha visto prendere una tumble et ci ha avvisati. Potresti aver avuto sogni de concussion molto strani; acqua prima, puis racconta solo quelli che ancora sembrano reali." \
        )
    }
    if state == nil || state.clinic_visits == 0 {
        return(
            "La clinica est guarda il mare. Dobro per trovare barche; meno dobro quand un aeroplano arriva senza appointment." \
        )
    }
    if state.clinic_visits == 1 {
        return "Respira piano. Niente cassé, solo un grande rumore. Acqua qui und meteo là—scegli acqua prima."
    }
    switch state.clinic_visits % 3 {
    case 0:
        return fmt.tprintf(
            "Encore tu, visita numero %d. Il mare pardonne beaucoup, mais non conserva i miei records.",
            state.clinic_visits,
        )
    case 1:
        return fmt.tprintf(
            "Visita numero %d. Acqua aspetta al letto, meteo sul muro, und il mare non aspetta nessuno. Scegli la prima.",
            state.clinic_visits,
        )
    case 2:
        return fmt.tprintf(
            "Encore, numero %d. Ho mosso l'acqua plus vicina et l'appointment book plus lontano. Una di noi sta imparando.",
            state.clinic_visits,
        )
    }
    return ""
}

anica_water_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Exactement. Acqua prima, puis meteo, puis decisioni. L'ordine è abbastanza piccolo da ricordare dopo un grande rumore." \
    )
}

anica_sea_close :: proc(_: ^dialogue.Context) -> string {
    return "Il mare conta barche, non bicchieri. Bevi questo; io lo registro dove la marea non può éditer."
}

anica_repeat_water_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Hai ricordato acqua. Bene—una instruction meno tra il rumore et buon senso. Bevi; puis discutiamo il resto." \
    )
}

anica_repeat_bed_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Zero reservations. Mais ho mosso il bicchiere sulla stessa shelf due volte. È hospitality sufficiente; non farne tradition." \
    )
}

toma_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil {
        return "Posta dell'isola west, dobro. Ogni traversata conta, même quand la postbag è leggera."
    }
    post_cycle := state.repeat_deliveries / 2 % 3
    if state.delivery.active && state.delivery.to == .Toma {
        switch post_cycle {
        case 0:
            return(
                "Ah, la posta dell'isola est. Lamp glass sotto, dinner note di Lena sopra, und pane separato. Prepara correttamente; naturalmente, io le ho insegnato." \
            )
        case 1:
            return(
                "La posta dell'isola est, dobro. Lena ha protetto ogni lamp glass con i miei vecchi weather reports. Enfin, un uso accurato." \
            )
        case 2:
            return(
                "Posta da Lena. Scrive eat before sorting all'esterno, così même un postmaster non può classificarla male." \
            )
        }
    }
    if !state.delivery.active && state.repeat_deliveries % 2 == 0 {
        switch post_cycle {
        case 0:
            return(
                "Lena aspetta questa island post: pane, postcards, et un fiore pressato. Portala est avant che il pane diventi pietra." \
            )
        case 1:
            return(
                "Island post per Lena: due postcards, pane fresco, und la sua blue pencil. Dice che l'ho presa; les records dicono niente." \
            )
        case 2:
            return(
                "Island post di Lena: pane sopra, postcards piatte, et una basil cutting. Dille che ha survécu alla mia supervision." \
            )
        }
    }
    switch post_cycle {
    case 0:
        return "La postbag repose, mais io non. Ogni lettre trova posto avant che la bura entri dalla door."
    case 1:
        return "Ancora zero island post. Lena chiamerebbe questa shelf storta; dalla sua isola, forse sembra droite."
    case 2:
        return "Postbag vuota, ledger équilibré, pane nascosto dai gulls. Un raro trionfo amministrativo."
    }
    return ""
}

lena_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil {
        return "Posta dell'isola est: lettres sopra, lamp glass sotto, und pane sempre visibile."
    }
    post_cycle := state.repeat_deliveries / 2 % 3
    if state.delivery.active && state.delivery.to == .Lena {
        switch post_cycle {
        case 0:
            return(
                "La posta dell'isola west est arrivée, dobro. Pane qui, postcards là, und il fiore—delicato, ha viaggiato assez." \
            )
        case 1:
            return "La mia blue pencil, enfin. Toma chiama questo ritorno; i bite marks lo chiamano confessione."
        case 2:
            return(
                "Pane, postcards, et basilico. Toma ha preparato le radici in un customs form—suolo ufficiale, apparentemente." \
            )
        }
    }
    if !state.delivery.active && state.repeat_deliveries % 2 == 1 {
        switch post_cycle {
        case 0:
            return(
                "Toma aspetta questa island post: lamp glass bien protetta, et una dinner note. Portala west; il glass non sa nuotare." \
            )
        case 1:
            return(
                "Island post per Toma: lamp glass, i suoi weather reports, et una note marcata SUPPER. Mantieni la parola visibile." \
            )
        case 2:
            return(
                "Island post di Toma: lamp glass sotto, dinner note sopra, und zero basilico. Prima deve provare di avere irrigato l'ultimo." \
            )
        }
    }
    switch post_cycle {
    case 0:
        return "Tutto est classé, quasi. Les lettres aspettano calme; solo il pane pretende urgenza."
    case 1:
        return "Zero island post oggi. Io apprezzo la custodia temporaire di tutte le mie pencils."
    case 2:
        return "Les shelves sono quiete. Toma diffiderebbe, donc non menziono niente."
    }
    return ""
}

toma_post_handoff_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Island post per Lena, eastbound. Mantieni la postbag asciutta et il pane visibile."
    switch state.repeat_deliveries / 2 % 3 {
    case 0:
        return(
            "Island post per Lena, eastbound: pane sopra, postcards piatte, fiore lontano dai gomiti. La postbag conosce la route; ricorda ai gulls." \
        )
    case 1:
        return(
            "Island post di Lena, con la blue pencil dentro. Mantieni la postbag asciutta—et se domanda, i bite marks precedono la mia administration." \
        )
    case 2:
        return(
            "Eastbound island post: pane, postcards, basilico verticale. Si la cutting inclina, dite a Lena che il vento ha voté." \
        )
    }
    return ""
}

lena_post_handoff_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Island post per Toma, westbound. Lamp glass sotto, dinner note sopra."
    switch state.repeat_deliveries / 2 % 3 {
    case 0:
        return(
            "Island post per Toma, westbound: lamp glass sotto, dinner note sopra. Mantieni SUPPER visibile; rispetta les capitales." \
        )
    case 1:
        return(
            "Island post di Toma. I suoi weather reports proteggono la lamp glass; è la forecast più sicura che abbiano prodotto." \
        )
    case 2:
        return(
            "Westbound island post: lamp glass, dinner note, zero basilico. Non aggiungere sympathy; Toma può irrigarlo lui-même." \
        )
    }
    return ""
}

toma_post_handoff_orderly_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Dobro. Mantieni pane alto, postcards piatte, und il fiore protetto. L'exactitude è gentilezza con linee numerate." \
    )
}

toma_post_handoff_improvise_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Acceptable. Il mare può modificare la route, mais non la postbag. Proteggi le cose di Lena; accusa les gulls solo con evidence." \
    )
}

lena_post_handoff_orderly_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Bien. Lamp glass sotto, note sopra, und zero eroismi tra loro. L'ordine fa arrivare cose fragile senza discorsi." \
    )
}

lena_post_handoff_supper_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Enfin, un corriere che comprende priorità. Si Toma protesta, ricorda che les capitales superano il ledger." \
    )
}

toma_post_receipt_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.repeat_deliveries == 0 {
        return(
            "La postbag è arrivée asciutta. Lamp glass sotto, note sopra—Lena permetterà a entrambi di restare impiegati." \
        )
    }
    switch (state.repeat_deliveries - 1) / 2 % 3 {
    case 0:
        return(
            "Lamp glass intera, dinner note leggibile, pane saggiamente separato. Lena ha sottolineato SUPPER due volte; non è plus correspondance, è navigation." \
        )
    case 1:
        return(
            "Lamp glass intera, vecchi weather reports ritornati. Lena ha marcato ogni forecast falsa in blue pencil—molto educativo, totalement vendicativo." \
        )
    case 2:
        return(
            "Lamp glass intera, dinner note sopra, zero basilico. Ha disegnato un watering can accanto al mio nome. La subtilité ha lasciato la posta." \
        )
    }
    return ""
}

toma_post_orderly_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    cycle := 0
    if state != nil && state.repeat_deliveries > 0 {
        cycle = (state.repeat_deliveries - 1) / 2 % 3
    }
    switch cycle {
    case 0:
        return(
            "Ho observé. Angoli asciutti, stack dritta, niente crushed. Un postmaster nota la cura anche quand il ledger non ha colonna." \
        )
    case 1:
        return(
            "Ho observé. Weather reports piatti, lamp glass intera, und zero correction in blue pencil en route. Excellent restraint." \
        )
    case 2:
        return(
            "Ho observé. Glass sotto, note sopra, zero basilico non autorizzato. Même l'accusa del watering can è arrivée dritta." \
        )
    }
    return ""
}

toma_post_teasing_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    cycle := 0
    if state != nil && state.repeat_deliveries > 0 {
        cycle = (state.repeat_deliveries - 1) / 2 % 3
    }
    switch cycle {
    case 0:
        return(
            "Officiellement, la lamp glass aveva priorità. Non ufficialmente, ho letto SUPPER avant la crack. Non revisionare il ledger." \
        )
    case 1:
        return(
            "Lena ha ritornato ogni forecast con evidence. Ho inspectato la blue pencil prima—curiosità professionale, naturellement." \
        )
    case 2:
        return(
            "Il watering can era très chiaro. La lamp glass ha solo confirmato che il parcel è sopravvissuto; la mia réputation, non." \
        )
    }
    return ""
}

lena_post_receipt_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.repeat_deliveries == 0 {
        return(
            "La postbag è arrivée asciutta. Pane visibile, postcards piatte—Toma ha ricordato almeno la civilisation importante." \
        )
    }
    switch (state.repeat_deliveries - 1) / 2 % 3 {
    case 0:
        return(
            "Pane ancora morbido, postcards piatte, fiore pressato intact. Toma l'ha messo in una customs declaration; apparentemente la tendresse demande paperwork." \
        )
    case 1:
        return(
            "La mia blue pencil, enfin—plus pane et due postcards come testimoni. I bite marks hanno traversé il mare, non la justice." \
        )
    case 2:
        return(
            "Pane, postcards, et una basil cutting viva. Toma ha preparato le radici in suolo ufficiale et aggiunto tre instructions per sé." \
        )
    }
    return ""
}

lena_post_orderly_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    cycle := 0
    if state != nil && state.repeat_deliveries > 0 {
        cycle = (state.repeat_deliveries - 1) / 2 % 3
    }
    switch cycle {
    case 0:
        return(
            "Ho observé. Carta asciutta, pane morbido, ogni angolo rispettato. La cura è il postal mark che nessuno può contraffare." \
        )
    case 1:
        return(
            "Ho observé. Blue pencil asciutta, pane morbido, postcards quadrate. Même i bite marks di Toma sono arrivati dove registrati." \
        )
    case 2:
        return(
            "Ho observé. Basilico verticale, radici umide, customs form assurdamente piatto. La cura può survivre alla burocrazia." \
        )
    }
    return ""
}

lena_post_teasing_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    cycle := 0
    if state != nil && state.repeat_deliveries > 0 {
        cycle = (state.repeat_deliveries - 1) / 2 % 3
    }
    switch cycle {
    case 0:
        return(
            "Naturalmente. Toma supervise con due mani, puis scrive un form dicendo che il parcel si è arrangiato. Archivierò la testimonianza." \
        )
    case 1:
        return(
            "Personalmente, sì. Ha protetto la pencil comme gioielli reali, puis negato ogni bite mark in triplicato." \
        )
    case 2:
        return(
            "Toma ha supervisé il basilico finché ha acquisito paperwork. Io irrigo la plant et archivio la sua ansia." \
        )
    }
    return ""
}

zora_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if quest_is_active(state, .Weather_Reading) {
        return(
            "Le carte possono aspettare. Porta gli occhi all'airfield: weather reading prima, real sky secondo, decisione terza." \
        )
    }
    if state == nil || state.tarot_readings == 0 {
        return(
            "Ferme la persiana, piccolo corriere, que la bura mélange ya abbastanza. Die carte non commandano el mare; solamente indicano dónde der vento quiere girare." \
        )
    }
    if state.tarot_last_moment == tarot_moment(state) {
        return(
            "Die carte hanno ya parlé para questo vento. Ahora observe il cielo vero, und retourne cuando qualcosa cambia." \
        )
    }
    return "Siedi: der vento ha tourné desde l'ultima lecture; vediamo si las carte se ne sono accorte."
}

tarot_moment :: proc(state: ^State) -> u32 {
    if state == nil do return 0
    return u32(state.romance) * 8 + u32(state.repair) + 1
}

can_deal_tarot :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && (state.tarot_readings == 0 || state.tarot_last_moment != tarot_moment(state))
}

can_recall_tarot :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return(
        state != nil &&
        state.tarot_readings > 0 &&
        state.tarot_layout.count > 0 &&
        state.tarot_last_moment == tarot_moment(state) \
    )
}

tarot_card_omen :: proc(card: tarot.Card) -> string {
    id := int(card)
    switch {
    case id == 6:
        return "due persone deben choisir die medesima traversata"
    case id == 7:
        return "der voyage vuole mani firmes, nicht vitesse"
    case id == 9:
        return "una lampe solitaria puede encore guider qualcuno"
    case id == 10:
        return "die ruota tourne solamente cuando qualcuno la pousse"
    case id == 16:
        return "lo que semble rovina demande prima una inspection"
    case id == 17:
        return "una luce distante puede essere aussi una promessa"
    case id == 18:
        return "der meteo cache la mitad della route"
    case id == 19:
        return "la clarté va arriver mit il giorno"
    case id >= 22 && id < 36:
        return "der lavoro und il courage tirano nella même direction"
    case id >= 36 && id < 50:
        return "la affection voyage mejor in un recipiente simple"
    case id >= 50 && id < 64:
        return "una parola puede couper; una parola precisa sabe réparer"
    case id >= 64:
        return "die cosa concreta bajo la mano mérite confiance"
    }
    return "der changement è ya entrato dalla finestra"
}

zora_story_omen :: proc(state: ^State) -> string {
    if state == nil do return "Non inseguire der symbole; observe qué lo fait muovere."
    switch state.romance {
    case .Unintroduced:
        return "Due persone gardano las stesse ore auf rive diverse; todavía non chiamano cela attesa."
    case .First_Letter:
        return "Una lettre bien sigillata traverse el mare in mani que sanno tacere."
    case .Corresponding:
        return "Die distance devient piccola primero sur carta, puis sotto i piedi."
    case .Invitation:
        if state.repair != .Repaired {
            return "Canvas, vento, und un voyage deben être réparés prima della promessa."
        }
        return "Die route nel cielo est pronta; el courage doit solamente salire a bordo."
    case .Meeting:
        return "Due sedie bajo une tenda blu font menos ombra di una sedia vuota."
    case .Together:
        return "Tu conosci ya die route: pane all'andata, verre bien protetto al ritorno."
    }
    return ""
}

zora_reading_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.tarot_layout.count == 0 do return "Die table est vuota; algo ha déjà mangé la fortuna."
    first := state.tarot_layout.placements[0]
    direction := first.orientation == .Reversed ? "controvento" : "con il vento"
    switch state.tarot_layout.spread {
    case .Single:
        return fmt.tprintf("%s, %s.", tarot.card_name(first.card), direction)
    case .Three_Card:
        second := state.tarot_layout.placements[1]
        third := state.tarot_layout.placements[2]
        return fmt.tprintf(
            "Im passé: %s.\nPara ora: %s.\nRiva possible: %s.",
            tarot.card_name(first.card),
            tarot.card_name(second.card),
            tarot.card_name(third.card),
        )
    case .Celtic_Cross:
        crossing := state.tarot_layout.placements[1]
        shore := state.tarot_layout.placements[state.tarot_layout.count - 1]
        return fmt.tprintf(
            "Al cuore: %s.\nAuf la traversata: %s.\nÀ la riva distante: %s.",
            tarot.card_name(first.card),
            tarot.card_name(crossing.card),
            tarot.card_name(shore.card),
        )
    }
    return ""
}

zora_counsel_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.tarot_layout.count == 0 do return zora_story_omen(state)
    first := state.tarot_layout.placements[0]
    return fmt.tprintf(
        "Die prima carte te dice que %s.\nFür te, oggi: %s",
        tarot_card_omen(first.card),
        zora_story_omen(state),
    )
}

zora_recall_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.tarot_layout.count == 0 do return "Sin una carte auf la table, la memoria devient théâtre."
    first := state.tarot_layout.placements[0]
    direction := first.orientation == .Reversed ? "controvento" : "con il vento"
    return fmt.tprintf(
        "%s était prima, %s: misma carte, stesso vento.\nRicorda bien: %s",
        tarot.card_name(first.card),
        direction,
        zora_story_omen(state),
    )
}

zora_recall_act_close :: proc(_: ^dialogue.Context) -> string {
    return "Bene. Una carte que te retient alla table ha fallito. Ferme la persiana; die mondo aspetta."
}

zora_recall_sky_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Comme il faut. Der cielo cambia abiertamente; die carte parlano dopo. Prendi las due sul serio, aber adora nessuno." \
    )
}

has_friendometer :: proc(state: ^State) -> bool {
    if state == nil do return false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)
    return(
        state.quest.definition_id == catalog.definition.id &&
        quest.is_complete(&state.quest, &catalog.definition, quest_node_id(.Friendometer)) \
    )
}

needs_friendometer :: proc(ctx: ^dialogue.Context) -> bool {
    return !has_friendometer(state_from_context(ctx))
}

has_friendometer_context :: proc(ctx: ^dialogue.Context) -> bool {
    return has_friendometer(state_from_context(ctx))
}

mirna_text :: proc(ctx: ^dialogue.Context) -> string {
    if has_friendometer(state_from_context(ctx)) {
        return(
            "Ah, field researcher of mine! Friendometer, does it still to you record? Good. One scalar we have; causation, regrettably, still refuses." \
        )
    }
    return(
        "Finally! To me has arrived walking subject, socially movable and, almost certain am, not magnetic. Inside come—local science pockets of yours requires." \
    )
}

mirna_friendometer_text :: proc(_: ^dialogue.Context) -> string {
    return(
        "Friendship have I into scalar value put: for every observable positive act, one unit. This here is Friendometer—copper, glass, three springs, and superstition in it, certified, none." \
    )
}

mirna_friendometer_accept :: proc(ctx: ^dialogue.Context) {
    state := state_from_context(ctx)
    if state == nil do return
    _, _ = publish_quest_event(state, {kind = .Talk, key = "friendometer", target = "mirna"})
}

mirna_friendometer_practical_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Perfect. Something kind do, upward goes needle; nothing do, and control group have we. Go—with people speak, to them help, and dry carry what dry must remain." \
    )
}

mirna_results_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    total := state == nil ? 0 : state.friendship_points
    return fmt.tprintf(
        "Result current: %d. Moral judgment this is not—measure it is of positive acts which apparatus of mine has seen. With field work continue.",
        total,
    )
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
    if state == nil do return "Buongiorno. Les forni werden caldi avant que il porto se svegli."
    if state.delivery.active && state.delivery.to == .Niko {
        switch state.delivery.kind {
        case .First_Reply:
            return "Ah, sei de retour preko il mare. Tu as la reply di Iva con te?"
        case .Regatta_Acceptance:
            return "Der motor di Bojan ha traversé la baia al alba. È questa la regatta acceptance de Iva?"
        case .Repeat_Westbound:
            return "Le verre de lampe voyage malissimo preko il mare. Espero che Iva l'abbia preparato bolje di moi."
        case .None,
             .First_Letter,
             .Regatta_Invitation,
             .Repeat_Eastbound,
             .Clinic_Medicine,
             .Clinic_Linens,
             .Clinic_Water:
        }
    }
    switch state.romance {
    case .Unintroduced:
        if state.airfield_errand == .Eastbound || state.airfield_errand == .Completed {
            return "Quando retournes a est… tengo una sealed letter para Iva. L'enveloppe est piccola fuori, almeno."
        }
        return "La lampe dell'isola est clignote due volte avant alba. Iva garde il faro mentre die forni scaldano."
    case .First_Letter:
        return "La boîte di cardamomo sieht très sospetta quand qualcuno espera una risposta."
    case .Corresponding:
        return "La regatta demande un baker, claro. Questa regatta invitation va para Iva, gardienne du phare."
    case .Invitation:
        return "C'è una tenda blu am quai. Personne ne sait perché la inspecto cada giorno."
    case .Meeting:
        return "Iva ha trouvé la blue awning. Sie sembra plus petite con due persone dessous."
    case .Together:
        return "La posta dell'isola continue: Iva dit che le verre puede aspettare. Das pane nicht."
    }
    return ""
}

niko_delivery_reaction :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return ""
    if state.delivery.care == .Orderly {
        return(
            "Asciutta, piatta, und cada fold encore preciso. Tu portes una lettera wie Gerta porta un instrument: zero drama, tutta cura." \
        )
    }
    if state.delivery.care == .Expressive {
        return(
            "La lettera est intacta, aber arriva con l'aria de saber qualcosa. Très bien; certaines consegne devono conservare anche il silenzio." \
        )
    }
    switch state.delivery.kind {
    case .First_Reply:
        return "Elle ricordava la farina de mi première nota. Nicht la parte che aspettavo."
    case .Regatta_Acceptance:
        return "Elle viene. Debo lasciare la tenda comme si non l'avessi poliert."
    case .Repeat_Westbound:
        return "Le verre ha survécu, und sie ha incluso instructions para cena. Uno dei due est plus fragile."
    case .None, .First_Letter, .Regatta_Invitation, .Repeat_Eastbound, .Clinic_Medicine, .Clinic_Linens, .Clinic_Water:
        return "Grazie. Certaines cose arrivent bolje quand nadie le apre en route."
    }
    return ""
}

niko_handoff_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Garde la letter sealed sopra il spray. Iva wird comprendre el resto."
    switch state.delivery.kind {
    case .First_Letter:
        return(
            "Voilà: una sealed letter para Iva, verpackt accanto alla recette di cardamomo. Garde-la sopra il spray; l'encre hat menos courage que tu." \
        )
    case .Regatta_Invitation:
        return(
            "Questa regatta invitation est para Iva. La blue awning steht solo una volta, donc možda lei penserà che io la mentiono casualmente." \
        )
    case .Repeat_Eastbound:
        switch state.repeat_deliveries / 2 % 3 {
        case 0:
            return(
                "Para Iva: pane caldo, postcards, und un fiore pressé. Garde la package sopra il spray; sentiment hat pessima waterproofing." \
            )
        case 1:
            return(
                "Para Iva: pane, su blue measuring spoon, et cardamomo. Der spoon est emballé; mia spiegazione, nicht." \
            )
        case 2:
            return(
                "Para Iva: pane und una basil cutting. Garde les roots verticales; encouragement puede aggiungersi avec moderation." \
            )
        }
    case .None, .First_Reply, .Regatta_Acceptance, .Repeat_Westbound, .Clinic_Medicine, .Clinic_Linens, .Clinic_Water:
        return "Garde la letter sealed sopra il spray. Iva wird comprendre el resto."
    }
    return ""
}

niko_handoff_careful_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.delivery.kind == .Repeat_Eastbound {
        return(
            "Grazie. Pane sopra, postcards plates, fiore protégé. La package peut survivre il mare ohne diventare una storia." \
        )
    }
    return(
        "Grazie. Il mare puede leggere chaque riva, mais nicht questa letter. Garde il nome di Iva asciutto; el resto può arriver froissé." \
    )
}

niko_handoff_playful_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.delivery.kind == .Repeat_Eastbound {
        return "Naturellement. Un fiore, pane caldo, und zero evidence personale. Iva peut classificarli anders."
    }
    return(
        "Il n'y a zero evidence. Solo cardamomo, una sealed letter, und ein baker che ha pulito la farina da una manche. Completamente routine." \
    )
}

niko_together_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Iva zegt que l'horloge du phare gagne un minuto. Mein oven clock disagree, très forte."
    switch state.repeat_deliveries / 2 % 3 {
    case 0:
        return(
            "Iva zegt que l'horloge du phare gagne un minuto. Mein oven clock perde due. Entre nous, cena arrive exactement a tempo." \
        )
    case 1:
        return(
            "Sie ha retourné mi blue measuring spoon dentro trois couches di lamp paper. Très sicuro, totalmente inutile, unmistakably Iva." \
        )
    case 2:
        return(
            "Iva dice que basilico braucht acqua, non encouragement. Io fournisse entrambi; die plant n'a déclaré aucune préférence." \
        )
    }
    return ""
}

niko_together_rhythm_close :: proc(_: ^dialogue.Context) -> string {
    return "Un rhythm, sì: lampe, forno, postbag, supper. Rien romantique—solo excellente Planung mit cardamomo."
}

niko_together_experiment_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Écris successful in letras grandes, per favore. Iva archiviert la petite print accanto ai maintenance complaints." \
    )
}

niko_warm_close :: proc(_: ^dialogue.Context) -> string {
    return "Va bene. Io metto ein altro plateau dentro; attendre funciona meglio con lavoro utile."
}

niko_discreet_close :: proc(_: ^dialogue.Context) -> string {
    return "Bene. Una lettre sigillata mérite wenigstens una persona capaz de tacere."
}

meeting_iva_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.careful_deliveries > state.expressive_deliveries {
        return(
            "La tenda blu è exactement dove Niko l'ha descritta. Et ogni lettera arrivava asciutta, piatta, quasi troppo disciplinata per due persone così nerveuses." \
        )
    }
    if state != nil && state.expressive_deliveries > 0 {
        return(
            "La tenda blu è exactement dove Niko l'ha descritta. Le lettere arrivavano sigillate, mais sempre con un piccolo sorriso del corriere." \
        )
    }
    return(
        "La tenda blu è exactement dove Niko l'ha descritta. Bojan chiama il volo routine, mais un atterraggio routine usa tutte tre ruote, sì?" \
    )
}

meeting_niko_warm :: proc(_: ^dialogue.Context) -> string {
    return(
        "La terza ruota était dekorativ. Siediti, por favor; ho fatto genug pane pour una regatta und un aeroplano tardivo." \
    )
}

meeting_niko_discreet :: proc(_: ^dialogue.Context) -> string {
    return(
        "Alors non has visto niente, grazie. Solo ein baker, una gardienne du phare, und pranzo sotto una tenda ordinaria." \
    )
}

meeting_iva_warm_close :: proc(_: ^dialogue.Context) -> string {
    return "Ha contato il pane due volte und les minutes tre. Sono arrivata avant che finisse uno dei due."
}

meeting_iva_discreet_close :: proc(_: ^dialogue.Context) -> string {
    return "Una tenda très ordinaria. Niko ha lucidato la frame ieri—due volte, mit completa indifferenza."
}

iva_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Dobro jutro. La lampe è prête; il meteo non ancora."
    if state.delivery.active && state.delivery.to == .Iva {
        switch state.delivery.kind {
        case .First_Letter:
            return "Una lettre sigillata ha traversé tutto quel mare blu per trovare questo faro."
        case .Regatta_Invitation:
            return "La regatta invitation di Niko diventa plus droite quand finge di non essere nervoso."
        case .Repeat_Eastbound:
            return "La posta dell'isola profuma comme se Niko confondesse la route postale con una dispensa."
        case .None,
             .First_Reply,
             .Regatta_Acceptance,
             .Repeat_Westbound,
             .Clinic_Medicine,
             .Clinic_Linens,
             .Clinic_Water:
        }
    }
    switch state.romance {
    case .Unintroduced:
        return "Due lampi signalent acqua chiara. Uno sembrava toujours un poco solo."
    case .First_Letter:
        return "Ha ricordato il cardamomo. Bene, le phare può offrire la reply di Iva."
    case .Corresponding:
        return "La posta dell'isola west è devenue notevolmente punctual."
    case .Invitation:
        if state.repair == .Repaired {
            return(
                "Tu hai réparé l'aeroplano di Bojan avant che servisse. Grazie; ora puoi portare la regatta acceptance." \
            )
        }
        return "Io posso répondre a Niko, mais l'ala rotta non può portarmi. Nema regatta ancora."
    case .Meeting:
        return "L'isola west è plus rumorosa del phare. Niko, fortunatamente, non."
    case .Together:
        return "La posta dell'isola porta pane, comme se il mare fosse un problema che nutrire sempre résout."
    }
    return ""
}

iva_delivery_reaction :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return ""
    if state.delivery.care == .Orderly {
        return(
            "Carta asciutta, seal intero, ogni corner ancora droit. Una traversata calme è una forma très pratica di gentilezza." \
        )
    }
    if state.delivery.care == .Expressive {
        return(
            "Il seal è intero, pourtant la busta sembra avere acquisito una opinion en route. La metterò vicino alla lamp, con discrezione." \
        )
    }
    switch state.delivery.kind {
    case .First_Letter:
        return "Ha ricordato il cardamomo. Dite a Niko: due lampi, parce que uno si sentiva solo."
    case .Regatta_Invitation:
        if state.repair == .Repaired {
            return "L'aeroplano di Bojan è pronto. Grazie; la tua gentilezza precedente ha organizzato ma risposta."
        }
        return "Io andrei, mais l'aeroplano di Bojan mostra più cielo attraverso l'ala che sopra."
    case .Repeat_Eastbound:
        return "Pane, cartes postales, und un fiore. Ha preparato tre specie di meteo."
    case .None, .First_Reply, .Regatta_Acceptance, .Repeat_Westbound, .Clinic_Medicine, .Clinic_Linens, .Clinic_Water:
        return "Encore sigillata. Grazie per trattare la traversata comme parte della promessa."
    }
    return ""
}

iva_handoff_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Keep ma risposta sealed until Niko opens it on the other shore."
    switch state.delivery.kind {
    case .First_Reply:
        return(
            "My reply for Niko. It says due flashes, among other things. Keep ma risposta sealed until the west island." \
        )
    case .Regatta_Acceptance:
        return(
            "My regatta acceptance for Niko. The blue awning is sufficient; no need for him to construct una second awning from worry." \
        )
    case .Repeat_Westbound:
        switch (state.repeat_deliveries - 1) / 2 % 3 {
        case 0:
            return(
                "For Niko: lamp glass below, dinner note above. Keep la package dry; only one item survives being read in rain." \
            )
        case 1:
            return(
                "For Niko: lamp paper, his blue spoon, und a meteo note. He will dispute the forecast after returning the spoon." \
            )
        case 2:
            return(
                "For Niko: basil instructions, lamp glass, et one dinner note. The plant needs acqua; Niko needs underlining." \
            )
        }
    case .None, .First_Letter, .Regatta_Invitation, .Repeat_Eastbound, .Clinic_Medicine, .Clinic_Linens, .Clinic_Water:
        return "Keep ma risposta sealed until Niko opens it on the other shore."
    }
    return ""
}

iva_handoff_careful_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.delivery.kind == .Repeat_Westbound {
        return(
            "Dobro. Lamp glass below, note above, und dry corners. Niko may improvise dinner only after la package arrives." \
        )
    }
    return "Dobro. Una seal is a small lighthouse: it says where la message belongs, et where curious hands do not."
}

iva_handoff_lights_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.delivery.kind == .Repeat_Westbound {
        return "Follow them exactly enough to blame me. La glass is fragile; il dinner note only pretends to be."
    }
    return(
        "Due flashes, then west. If il meteo argues, trust la compass first; poetry is terrible navigation but good company." \
    )
}

iva_together_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Niko believes every lighthouse problem can be reduced by one warm loaf."
    switch state.repeat_deliveries / 2 % 3 {
    case 0:
        return(
            "Niko believes every lighthouse problem can be reduced by one warm loaf. The evidence is annoyingly favorable." \
        )
    case 1:
        return(
            "The west island remains noisy. But Niko has learned when silence means tea, und when it means more cardamom." \
        )
    case 2:
        return(
            "He labels each basil pot con the date and a heroic title. I water them; history may decide who is responsible." \
        )
    }
    return ""
}

iva_together_system_close :: proc(_: ^dialogue.Context) -> string {
    return "It does. Deux islands leave room for work, und one crossing keeps the important things deliberate."
}

iva_together_evidence_close :: proc(_: ^dialogue.Context) -> string {
    return "Correct. Evidence: fewer burnt loaves, better-watered basil, et one baker who now checks il meteo."
}

iva_warm_close :: proc(_: ^dialogue.Context) -> string {
    return "Non sorridere così al faro. Das encourage les gulls."
}

iva_discreet_close :: proc(_: ^dialogue.Context) -> string {
    return "Grazie. Le isole sono déjà piccole senza che les lettres diventino strade pubbliche."
}

bojan_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "L'aeroplano und io faisons repos. Tutto tranquillo, plus ou moins."
    switch state.repair {
    case .Not_Seen:
        return "L'atterraggio era perfekt. Le sol è arrivato troppo presto. Hai visto zero complication."
    case .Crash_Reported:
        return "Ora la versione officielle è breve; possiamo inspecter the wing honnêtement."
    case .Diagnosed:
        return(
            "Un pannello di canvas è déchiré. Io ho the canvas patch; tu hai mani plus ferme della mia réputation." \
        )
    case .Patched:
        return "Canvas patch tendu, wing ribs dritte, controles libres. Voilà: gira the propeller, con prudenza."
    case .Repaired:
        if state.romance == .Invitation {
            return "L'aereo è pronto pour Iva. Ho même pulito il seat che non mi appartiene."
        }
        return "Patch tendu, wing ribs dritte, controles libres. Basta—questa è notre ingénierie."
    }
    return ""
}

bojan_report_reaction :: proc(_: ^dialogue.Context) -> string {
    return(
        "Alors il report officiel è simple: pilota intact, orgoglio in riparazione. Vieni—inspect the wing, dove il canvas ha preso le sol." \
    )
}

bojan_inspect_reaction :: proc(_: ^dialogue.Context) -> string {
    return(
        "Voilà: un pannello canvas déchiré, nessuna rib rotta. Tieni la canvas patch alla luce; si passa il cielo, ricominciamo." \
    )
}

bojan_inspect_practical_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Esatto. La rib mantiene la forme della wing; il canvas impedisce al vento di entrare sans billet. Ripariamo solo ciò che ha fallito." \
    )
}

bojan_inspect_teasing_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Un autografo très costoso. Heureusement, le sol ha firmato solo il canvas; il mio orgoglio demande un preventivo separato." \
    )
}

bojan_patch_reaction :: proc(_: ^dialogue.Context) -> string {
    return(
        "Tira una volta lungo la seam—dobro. La patch resta piatta, les controles sono libres, und ora solo the propeller può protestare." \
    )
}

bojan_repair_reaction :: proc(_: ^dialogue.Context) -> string {
    return(
        "The propeller gira, il canvas tiene, tre ruote restano négociables. Grazie—questo aeroplano può portare plus delle mie scuse." \
    )
}

bojan_repair_controls_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Sì. La patch resta piatta, controles ritornano al centro, und the propeller protesta regolare. Quasi boring—perfetto." \
    )
}

bojan_repair_wheels_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "A temporary alliance. Tre wheels, one pilot, zero witnesses willing to certify the landing. We accept il miracle." \
    )
}

bojan_repaired_check_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "La canvas patch holds flat. One repair, many flights—that is a favorable argument."
    switch state.romance {
    case .Invitation:
        return(
            "La canvas patch holds flat, controles move free, und Iva's seat is clean. Mechanically ready; socially, ask another engineer." \
        )
    case .Meeting:
        return(
            "Iva arrived, la canvas patch stayed taut, et all three wheels participated. I have recorded two of these facts officially." \
        )
    case .Together:
        switch state.repeat_deliveries / 2 % 3 {
        case 0:
            return(
                "La patch has crossed the bay twelve times. Canvas remembers good hands; il pilot merely borrows the credit." \
            )
        case 1:
            return(
                "Iva marks every flight in a little meteo book. Beside my last landing she wrote: 'adequate, eventually.' Très scientific." \
            )
        case 2:
            return(
                "Wing tension equal, controls libres, no daylight where canvas belongs. Even la bura has failed to improve our repair." \
            )
        }
    case .Unintroduced, .First_Letter, .Corresponding:
        return "La canvas patch holds flat. One repair, many flights—that is a favorable argument."
    }
    return ""
}

bojan_repaired_practical_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "See these pencil marks? Same distance today as dopo the repair. When they separate, we work. Until then, we fly." \
    )
}

bojan_repaired_teasing_close :: proc(_: ^dialogue.Context) -> string {
    return(
        "Correct. La patch is quiet, dependable, et never describes the landing as 'perfekt.' I try not to resent canvas." \
    )
}

accept_delivery :: proc(ctx: ^dialogue.Context) { _ = begin_delivery(state_from_context(ctx)) }
accept_niko_repeat_delivery :: proc(ctx: ^dialogue.Context) {
    state := state_from_context(ctx)
    if begin_delivery(state) {
        state.delivery.from = .Niko
        state.delivery.to = .Iva
    }
}
accept_iva_repeat_delivery :: proc(ctx: ^dialogue.Context) {
    state := state_from_context(ctx)
    if begin_delivery(state) {
        state.delivery.from = .Iva
        state.delivery.to = .Niko
    }
}
accept_post_delivery :: proc(ctx: ^dialogue.Context) { _ = begin_post_delivery(state_from_context(ctx)) }
accept_clinic_medicine :: proc(ctx: ^dialogue.Context) {
    _ = begin_local_delivery(state_from_context(ctx), .Clinic_Medicine)
}
accept_clinic_linens :: proc(ctx: ^dialogue.Context) {
    _ = begin_local_delivery(state_from_context(ctx), .Clinic_Linens)
}
accept_clinic_water :: proc(ctx: ^dialogue.Context) {
    _ = begin_local_delivery(state_from_context(ctx), .Clinic_Water)
}
accept_weather_errand :: proc(ctx: ^dialogue.Context) { _ = accept_weather_reading(state_from_context(ctx)) }
complete_vesna_delivery :: proc(ctx: ^dialogue.Context) { _ = complete_delivery(state_from_context(ctx), .Vesna) }
complete_anica_delivery :: proc(ctx: ^dialogue.Context) { _ = complete_delivery(state_from_context(ctx), .Anica) }
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

can_begin_niko_repeat_delivery :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .Together && can_begin_niko_delivery(ctx)
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

can_begin_iva_repeat_delivery :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .Together && can_begin_iva_delivery(ctx)
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
has_repeat_for_iva :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return has_repeat_eastbound(ctx) && state.delivery.to == .Iva
}
has_repeat_for_niko :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return has_repeat_westbound(ctx) && state.delivery.to == .Niko
}
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

quest_is_available :: proc(state: ^State, node: Quest_Node) -> bool {
    if state == nil || !ensure_quest_progress(state) do return false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)
    return quest.status(&state.quest, &catalog.definition, quest_node_id(node)) == .Available
}

quest_is_active :: proc(state: ^State, node: Quest_Node) -> bool {
    if state == nil || !ensure_quest_progress(state) do return false
    catalog: Quest_Catalog
    init_quest_catalog(&catalog)
    return quest.status(&state.quest, &catalog.definition, quest_node_id(node)) == .Active
}

can_accept_weather_errand :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return(
        state != nil &&
        state.tarot_readings == 0 &&
        state.romance == .Unintroduced &&
        quest_is_available(state, .Weather_Reading) \
    )
}

can_accept_clinic_medicine :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return(
        state != nil &&
        state.clinic_visits == 0 &&
        !state.delivery.active &&
        quest_is_available(state, .Clinic_Medicine) \
    )
}

can_accept_clinic_linens :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return(
        state != nil &&
        state.clinic_visits == 0 &&
        !state.delivery.active &&
        quest_is_available(state, .Clinic_Linens) \
    )
}

can_accept_clinic_water :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return(
        state != nil &&
        state.clinic_visits == 0 &&
        !state.delivery.active &&
        quest_is_available(state, .Clinic_Water) \
    )
}

has_clinic_medicine :: proc(ctx: ^dialogue.Context) -> bool {
    return delivery_is(ctx, .Clinic_Medicine)
}

has_clinic_linens :: proc(ctx: ^dialogue.Context) -> bool {
    return delivery_is(ctx, .Clinic_Linens)
}

has_clinic_water :: proc(ctx: ^dialogue.Context) -> bool {
    return delivery_is(ctx, .Clinic_Water)
}

can_hold_meeting :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .Meeting && !state.delivery.active
}

is_together :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .Together && !state.delivery.active
}

is_repaired :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.repair == .Repaired
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
    case .Mirna:
        return !has_friendometer(state)
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
    niko_root_choices:           [9]dialogue.Choice,
    niko_reaction_choices:       [2]dialogue.Choice,
    niko_warm_choices:           [1]dialogue.Choice,
    niko_discreet_choices:       [1]dialogue.Choice,
    niko_handoff_choices:        [2]dialogue.Choice,
    niko_handoff_close_choices:  [1]dialogue.Choice,
    niko_together_choices:       [2]dialogue.Choice,
    niko_together_close_choices: [1]dialogue.Choice,
    meeting_choices:             [2]dialogue.Choice,
    meeting_warm_choices:        [1]dialogue.Choice,
    meeting_discreet_choices:    [1]dialogue.Choice,
    meeting_finish_choices:      [1]dialogue.Choice,
    iva_root_choices:            [8]dialogue.Choice,
    iva_reaction_choices:        [2]dialogue.Choice,
    iva_warm_choices:            [1]dialogue.Choice,
    iva_discreet_choices:        [1]dialogue.Choice,
    iva_handoff_choices:         [2]dialogue.Choice,
    iva_handoff_close_choices:   [1]dialogue.Choice,
    iva_together_choices:        [2]dialogue.Choice,
    iva_together_close_choices:  [1]dialogue.Choice,
    bojan_choices:               [6]dialogue.Choice,
    bojan_report_choices:        [1]dialogue.Choice,
    bojan_inspect_choices:       [2]dialogue.Choice,
    bojan_inspect_close_choices: [1]dialogue.Choice,
    bojan_patch_choices:         [1]dialogue.Choice,
    bojan_repair_choices:        [2]dialogue.Choice,
    bojan_repair_close_choices:  [1]dialogue.Choice,
    bojan_check_choices:         [2]dialogue.Choice,
    bojan_check_close_choices:   [1]dialogue.Choice,
    zora_choices:                [6]dialogue.Choice,
    zora_reading_choices:        [2]dialogue.Choice,
    zora_counsel_choices:        [1]dialogue.Choice,
    zora_recall_choices:         [2]dialogue.Choice,
    zora_recall_close_choices:   [1]dialogue.Choice,
    vesna_choices:               [6]dialogue.Choice,
    vesna_close_choices:         [1]dialogue.Choice,
    petar_choices:               [5]dialogue.Choice,
    petar_close_choices:         [1]dialogue.Choice,
    anica_choices:               [7]dialogue.Choice,
    anica_close_choices:         [1]dialogue.Choice,
    toma_choices:                [3]dialogue.Choice,
    toma_handoff_choices:        [2]dialogue.Choice,
    toma_handoff_close_choices:  [1]dialogue.Choice,
    toma_receipt_choices:        [2]dialogue.Choice,
    toma_close_choices:          [1]dialogue.Choice,
    lena_choices:                [3]dialogue.Choice,
    lena_handoff_choices:        [2]dialogue.Choice,
    lena_handoff_close_choices:  [1]dialogue.Choice,
    lena_receipt_choices:        [2]dialogue.Choice,
    lena_close_choices:          [1]dialogue.Choice,
    mirna_choices:               [3]dialogue.Choice,
    mirna_friendometer_choices:  [2]dialogue.Choice,
    mirna_close_choices:         [1]dialogue.Choice,
    niko_nodes:                  [15]dialogue.Node,
    iva_nodes:                   [10]dialogue.Node,
    bojan_nodes:                 [12]dialogue.Node,
    zora_nodes:                  [6]dialogue.Node,
    vesna_nodes:                 [5]dialogue.Node,
    petar_nodes:                 [5]dialogue.Node,
    anica_nodes:                 [5]dialogue.Node,
    toma_nodes:                  [7]dialogue.Node,
    lena_nodes:                  [7]dialogue.Node,
    mirna_nodes:                 [4]dialogue.Node,
    niko:                        dialogue.Definition,
    iva:                         dialogue.Definition,
    bojan:                       dialogue.Definition,
    zora:                        dialogue.Definition,
    vesna:                       dialogue.Definition,
    petar:                       dialogue.Definition,
    anica:                       dialogue.Definition,
    toma:                        dialogue.Definition,
    lena:                        dialogue.Definition,
    mirna:                       dialogue.Definition,
}

init_catalog :: proc(catalog: ^Catalog) {
    if catalog == nil do return
    catalog^ = {}

    catalog.niko_root_choices = {
        dialogue.choice("Give Niko Iva's reply.", 1, has_first_reply, complete_niko_delivery),
        dialogue.choice("Give Niko Iva's regatta acceptance.", 1, has_regatta_acceptance, complete_niko_delivery),
        dialogue.choice("Give Niko Iva's package.", 1, has_repeat_for_niko, complete_niko_delivery),
        dialogue.choice(
            "I'll carry your sealed letter to Iva.",
            9,
            condition = can_begin_first_letter,
            effect = accept_delivery,
        ),
        dialogue.choice(
            "I'll take Iva the regatta invitation.",
            9,
            condition = can_begin_regatta_invitation,
            effect = accept_delivery,
        ),
        dialogue.choice(
            "I'll carry the next package to Iva.",
            9,
            condition = can_begin_niko_repeat_delivery,
            effect = accept_niko_repeat_delivery,
        ),
        dialogue.choice("Stay under the awning.", 4, can_hold_meeting),
        dialogue.choice("How are things beneath the blue awning?", 10, is_together),
        dialogue.choice("I'll leave you to your work."),
    }
    catalog.niko_reaction_choices = {
        dialogue.choice("You look pleased.", 2),
        dialogue.choice("The letter stayed sealed.", 3),
    }
    catalog.niko_warm_choices[0] = dialogue.choice("Safe crossing, Niko.")
    catalog.niko_discreet_choices[0] = dialogue.choice("Not a word from me.")
    catalog.meeting_choices = {
        dialogue.choice("The awning suits you both.", 5),
        dialogue.choice("I saw only an ordinary arrival.", 6),
    }
    catalog.meeting_warm_choices[0] = dialogue.choice("And enough bread for a delayed plane.", 7)
    catalog.meeting_discreet_choices[0] = dialogue.choice("I can forget the landing, not the bread.", 8)
    catalog.meeting_finish_choices[0] = dialogue.choice("Enjoy the regatta.", effect = finish_meeting)
    catalog.niko_handoff_choices = {
        dialogue.choice("I'll keep it dry and in order.", 13, effect = choose_orderly_cargo),
        dialogue.choice("I'll ignore any personal evidence.", 14, effect = choose_expressive_cargo),
    }
    catalog.niko_handoff_close_choices[0] = dialogue.choice("East island, then.")
    catalog.niko_together_choices = {
        dialogue.choice("You found a good rhythm.", 11),
        dialogue.choice("I'll call the experiment successful.", 12),
    }
    catalog.niko_together_close_choices[0] = dialogue.choice("I'll leave the scheduling to you.")
    catalog.niko_nodes = {
        dialogue.node("niko", niko_text, catalog.niko_root_choices[:], niko_speaker),
        dialogue.node("niko-reaction", niko_delivery_reaction, catalog.niko_reaction_choices[:], niko_speaker),
        dialogue.node("niko-warm", niko_warm_close, catalog.niko_warm_choices[:], niko_speaker),
        dialogue.node("niko-discreet", niko_discreet_close, catalog.niko_discreet_choices[:], niko_speaker),
        dialogue.node("meeting-iva", meeting_iva_text, catalog.meeting_choices[:], iva_speaker),
        dialogue.node("meeting-niko", meeting_niko_warm, catalog.meeting_warm_choices[:], niko_speaker),
        dialogue.node(
            "meeting-niko-discreet",
            meeting_niko_discreet,
            catalog.meeting_discreet_choices[:],
            niko_speaker,
        ),
        dialogue.node("meeting-iva-warm", meeting_iva_warm_close, catalog.meeting_finish_choices[:], iva_speaker),
        dialogue.node(
            "meeting-iva-discreet",
            meeting_iva_discreet_close,
            catalog.meeting_finish_choices[:],
            iva_speaker,
        ),
        dialogue.node("niko-handoff", niko_handoff_text, catalog.niko_handoff_choices[:], niko_speaker),
        dialogue.node("niko-together", niko_together_text, catalog.niko_together_choices[:], niko_speaker),
        dialogue.node(
            "niko-together-rhythm",
            niko_together_rhythm_close,
            catalog.niko_together_close_choices[:],
            niko_speaker,
        ),
        dialogue.node(
            "niko-together-experiment",
            niko_together_experiment_close,
            catalog.niko_together_close_choices[:],
            niko_speaker,
        ),
        dialogue.node(
            "niko-handoff-careful",
            niko_handoff_careful_close,
            catalog.niko_handoff_close_choices[:],
            niko_speaker,
        ),
        dialogue.node(
            "niko-handoff-playful",
            niko_handoff_playful_close,
            catalog.niko_handoff_close_choices[:],
            niko_speaker,
        ),
    }
    catalog.niko = {
        id    = "niko",
        nodes = catalog.niko_nodes[:],
    }

    catalog.iva_root_choices = {
        dialogue.choice("Give Iva Niko's sealed letter.", 1, has_first_letter, complete_iva_delivery),
        dialogue.choice("Give Iva Niko's regatta invitation.", 1, has_regatta_invitation, complete_iva_delivery),
        dialogue.choice("Give Iva Niko's package.", 1, has_repeat_for_iva, complete_iva_delivery),
        dialogue.choice("I'll carry your reply to Niko.", 4, can_begin_first_reply, accept_delivery),
        dialogue.choice(
            "I'll take Niko the regatta acceptance.",
            4,
            condition = can_begin_regatta_acceptance,
            effect = accept_delivery,
        ),
        dialogue.choice(
            "I'll carry the next package to Niko.",
            4,
            condition = can_begin_iva_repeat_delivery,
            effect = accept_iva_repeat_delivery,
        ),
        dialogue.choice("How is the west island treating you?", 5, is_together),
        dialogue.choice("I'll leave you to tend the lamp."),
    }
    catalog.iva_reaction_choices = {
        dialogue.choice("The lamp seems especially cheerful.", 2),
        dialogue.choice("The letter stayed sealed.", 3),
    }
    catalog.iva_warm_choices[0] = dialogue.choice("Keep the light burning, Iva.")
    catalog.iva_discreet_choices[0] = dialogue.choice("Not a word from me.")
    catalog.iva_handoff_choices = {
        dialogue.choice("I'll keep everything dry and intact.", 8, effect = choose_orderly_cargo),
        dialogue.choice("I'll follow your packing instructions.", 9, effect = choose_expressive_cargo),
    }
    catalog.iva_handoff_close_choices[0] = dialogue.choice("West island, then.")
    catalog.iva_together_choices = {
        dialogue.choice("The system seems to suit you both.", 6),
        dialogue.choice("I'll trust your evidence.", 7),
    }
    catalog.iva_together_close_choices[0] = dialogue.choice("I'll leave you to the next crossing.")
    catalog.iva_nodes = {
        dialogue.node("iva", iva_text, catalog.iva_root_choices[:], iva_speaker),
        dialogue.node("iva-reaction", iva_delivery_reaction, catalog.iva_reaction_choices[:], iva_speaker),
        dialogue.node("iva-warm", iva_warm_close, catalog.iva_warm_choices[:], iva_speaker),
        dialogue.node("iva-discreet", iva_discreet_close, catalog.iva_discreet_choices[:], iva_speaker),
        dialogue.node("iva-handoff", iva_handoff_text, catalog.iva_handoff_choices[:], iva_speaker),
        dialogue.node("iva-together", iva_together_text, catalog.iva_together_choices[:], iva_speaker),
        dialogue.node(
            "iva-together-system",
            iva_together_system_close,
            catalog.iva_together_close_choices[:],
            iva_speaker,
        ),
        dialogue.node(
            "iva-together-evidence",
            iva_together_evidence_close,
            catalog.iva_together_close_choices[:],
            iva_speaker,
        ),
        dialogue.node(
            "iva-handoff-careful",
            iva_handoff_careful_close,
            catalog.iva_handoff_close_choices[:],
            iva_speaker,
        ),
        dialogue.node(
            "iva-handoff-lights",
            iva_handoff_lights_close,
            catalog.iva_handoff_close_choices[:],
            iva_speaker,
        ),
    }
    catalog.iva = {
        id    = "iva",
        nodes = catalog.iva_nodes[:],
    }

    catalog.bojan_choices = {
        dialogue.choice("I saw the whole thing.", 1, can_report_crash, note_crash),
        dialogue.choice("Let's inspect the wing.", 2, can_inspect_crash, inspect_crash),
        dialogue.choice("Apply the canvas patch.", 3, can_patch_wing, patch_wing),
        dialogue.choice("Turn the propeller.", 4, can_verify_repair, confirm_repair),
        dialogue.choice("How is our canvas patch holding?", 5, is_repaired),
        dialogue.choice("I'll leave you to it."),
    }
    catalog.bojan_report_choices[0] = dialogue.choice("Show me where the canvas tore.", 0)
    catalog.bojan_inspect_choices = {
        dialogue.choice("The rib is sound; only the canvas tore.", 8),
        dialogue.choice("The ground signed its name here.", 9),
    }
    catalog.bojan_inspect_close_choices[0] = dialogue.choice("Let's fit the canvas patch.", 0)
    catalog.bojan_patch_choices[0] = dialogue.choice("Let's test the controls.", 0)
    catalog.bojan_repair_choices = {
        dialogue.choice("The controls move cleanly.", 10),
        dialogue.choice("All three wheels survived.", 11),
    }
    catalog.bojan_repair_close_choices[0] = dialogue.choice("Then the aeroplano is ready.")
    catalog.bojan_check_choices = {
        dialogue.choice("Show me the inspection marks.", 6),
        dialogue.choice("The patch outperforms its pilot.", 7),
    }
    catalog.bojan_check_close_choices[0] = dialogue.choice("Keep it out of the ground.")
    catalog.bojan_nodes = {
        dialogue.node("bojan", bojan_text, catalog.bojan_choices[:], bojan_speaker),
        dialogue.node("bojan-report", bojan_report_reaction, catalog.bojan_report_choices[:], bojan_speaker),
        dialogue.node("bojan-inspect", bojan_inspect_reaction, catalog.bojan_inspect_choices[:], bojan_speaker),
        dialogue.node("bojan-patch", bojan_patch_reaction, catalog.bojan_patch_choices[:], bojan_speaker),
        dialogue.node("bojan-repaired", bojan_repair_reaction, catalog.bojan_repair_choices[:], bojan_speaker),
        dialogue.node("bojan-check", bojan_repaired_check_text, catalog.bojan_check_choices[:], bojan_speaker),
        dialogue.node(
            "bojan-check-practical",
            bojan_repaired_practical_close,
            catalog.bojan_check_close_choices[:],
            bojan_speaker,
        ),
        dialogue.node(
            "bojan-check-teasing",
            bojan_repaired_teasing_close,
            catalog.bojan_check_close_choices[:],
            bojan_speaker,
        ),
        dialogue.node(
            "bojan-inspect-practical",
            bojan_inspect_practical_close,
            catalog.bojan_inspect_close_choices[:],
            bojan_speaker,
        ),
        dialogue.node(
            "bojan-inspect-teasing",
            bojan_inspect_teasing_close,
            catalog.bojan_inspect_close_choices[:],
            bojan_speaker,
        ),
        dialogue.node(
            "bojan-repair-controls",
            bojan_repair_controls_close,
            catalog.bojan_repair_close_choices[:],
            bojan_speaker,
        ),
        dialogue.node(
            "bojan-repair-wheels",
            bojan_repair_wheels_close,
            catalog.bojan_repair_close_choices[:],
            bojan_speaker,
        ),
    }
    catalog.bojan = {
        id    = "bojan",
        nodes = catalog.bojan_nodes[:],
    }

    catalog.zora_choices = {
        dialogue.choice("Which way is the wind blowing?", 1, can_deal_tarot, deal_single),
        dialogue.choice("Past, present, and possible shore.", 1, can_deal_tarot, deal_three),
        dialogue.choice("I have time. Lay out the full cross.", 1, can_deal_tarot, deal_cross),
        dialogue.choice("Remind me what I should watch for.", 3, can_recall_tarot),
        dialogue.choice("Another time, grazie."),
        dialogue.choice(
            "Get an airfield weather reading.",
            condition = can_accept_weather_errand,
            effect = accept_weather_errand,
        ),
    }
    catalog.zora_reading_choices = {
        dialogue.choice("What should I watch for?", 2),
        dialogue.choice("Enough cards. I'll watch the real sky."),
    }
    catalog.zora_counsel_choices[0] = dialogue.choice("Then I'll choose the next crossing.")
    catalog.zora_recall_choices = {
        dialogue.choice("I'll act before asking the cards again.", 4),
        dialogue.choice("I'll trust the sky more than the cards.", 5),
    }
    catalog.zora_recall_close_choices[0] = dialogue.choice("Then I'll get moving.")
    catalog.zora_nodes = {
        dialogue.node("zora", zora_text, catalog.zora_choices[:], zora_speaker),
        dialogue.node("zora-reading", zora_reading_text, catalog.zora_reading_choices[:], zora_speaker),
        dialogue.node("zora-counsel", zora_counsel_text, catalog.zora_counsel_choices[:], zora_speaker),
        dialogue.node("zora-recall", zora_recall_text, catalog.zora_recall_choices[:], zora_speaker),
        dialogue.node("zora-recall-act", zora_recall_act_close, catalog.zora_recall_close_choices[:], zora_speaker),
        dialogue.node("zora-recall-sky", zora_recall_sky_close, catalog.zora_recall_close_choices[:], zora_speaker),
    }
    catalog.zora = {
        id    = "zora",
        nodes = catalog.zora_nodes[:],
    }

    catalog.mirna_choices = {
        dialogue.choice("What do my pockets have to do with science?", 1, needs_friendometer),
        dialogue.choice("How are the results looking?", 3, has_friendometer_context),
        dialogue.choice("I'll leave you to your research."),
    }
    catalog.mirna_friendometer_choices = {
        dialogue.choice("Give it here. I'll test it.", 2, effect = mirna_friendometer_accept),
        dialogue.choice("That sounds deeply unscientific.", 2, effect = mirna_friendometer_accept),
    }
    catalog.mirna_close_choices[0] = dialogue.choice("Time for field work.")
    catalog.mirna_nodes = {
        dialogue.node("mirna", mirna_text, catalog.mirna_choices[:], mirna_speaker),
        dialogue.node(
            "mirna-friendometer",
            mirna_friendometer_text,
            catalog.mirna_friendometer_choices[:],
            mirna_speaker,
        ),
        dialogue.node(
            "mirna-friendometer-close",
            mirna_friendometer_practical_close,
            catalog.mirna_close_choices[:],
            mirna_speaker,
        ),
        dialogue.node("mirna-results", mirna_results_text, catalog.mirna_close_choices[:], mirna_speaker),
    }
    catalog.mirna = {
        id    = "mirna",
        nodes = catalog.mirna_nodes[:],
    }

    catalog.vesna_choices = {
        dialogue.choice("Thanks, doctor. I'll take it slower.", 1, clinic_is_first_visit),
        dialogue.choice("The landing looked softer from above.", 2, clinic_is_first_visit),
        dialogue.choice("I checked the weather. It wasn't enough.", 3, clinic_is_repeat_visit),
        dialogue.choice("I remembered where my glasses go.", 4, clinic_is_repeat_visit),
        dialogue.choice(
            "Carry the clinic medicine east.",
            condition = can_accept_clinic_medicine,
            effect = accept_clinic_medicine,
        ),
        dialogue.choice(
            "Give Vesna the sealed water.",
            condition = has_clinic_water,
            effect = complete_vesna_delivery,
        ),
    }
    catalog.vesna_close_choices[0] = dialogue.choice("I'll check the weather first.")
    catalog.vesna_nodes = {
        dialogue.node("vesna", vesna_text, catalog.vesna_choices[:], vesna_speaker),
        dialogue.node("vesna-care", vesna_care_close, catalog.vesna_close_choices[:], vesna_speaker),
        dialogue.node("vesna-joke", vesna_joke_close, catalog.vesna_close_choices[:], vesna_speaker),
        dialogue.node("vesna-repeat-honest", vesna_repeat_honest_close, catalog.vesna_close_choices[:], vesna_speaker),
        dialogue.node("vesna-repeat-memory", vesna_repeat_memory_close, catalog.vesna_close_choices[:], vesna_speaker),
    }
    catalog.vesna = {
        id    = "vesna",
        nodes = catalog.vesna_nodes[:],
    }

    catalog.petar_choices = {
        dialogue.choice("I'll use the door next time.", 1, clinic_is_first_visit),
        dialogue.choice("The window was closer.", 2, clinic_is_first_visit),
        dialogue.choice("The door was not involved this time.", 3, clinic_is_repeat_visit),
        dialogue.choice("Do the linens recognize me now?", 4, clinic_is_repeat_visit),
        dialogue.choice(
            "Carry the dry clinic linens east.",
            condition = can_accept_clinic_linens,
            effect = accept_clinic_linens,
        ),
    }
    catalog.petar_close_choices[0] = dialogue.choice("I'll keep the linens out of it.")
    catalog.petar_nodes = {
        dialogue.node("petar", petar_text, catalog.petar_choices[:], petar_speaker),
        dialogue.node("petar-door", petar_door_close, catalog.petar_close_choices[:], petar_speaker),
        dialogue.node("petar-window", petar_window_close, catalog.petar_close_choices[:], petar_speaker),
        dialogue.node("petar-repeat-door", petar_repeat_door_close, catalog.petar_close_choices[:], petar_speaker),
        dialogue.node("petar-repeat-linens", petar_repeat_linens_close, catalog.petar_close_choices[:], petar_speaker),
    }
    catalog.petar = {
        id    = "petar",
        nodes = catalog.petar_nodes[:],
    }

    catalog.anica_choices = {
        dialogue.choice("Water first. Understood.", 1, clinic_is_first_visit),
        dialogue.choice("I thought the sea was keeping count.", 2, clinic_is_first_visit),
        dialogue.choice("Water first. I remembered.", 3, clinic_is_repeat_visit),
        dialogue.choice("Should I reserve this bed by name?", 4, clinic_is_repeat_visit),
        dialogue.choice(
            "Give Anica the clinic medicine.",
            condition = has_clinic_medicine,
            effect = complete_anica_delivery,
        ),
        dialogue.choice(
            "Give Anica the dry clinic linens.",
            condition = has_clinic_linens,
            effect = complete_anica_delivery,
        ),
        dialogue.choice(
            "Carry the sealed water west.",
            condition = can_accept_clinic_water,
            effect = accept_clinic_water,
        ),
    }
    catalog.anica_close_choices[0] = dialogue.choice("I'll make the next appointment quieter.")
    catalog.anica_nodes = {
        dialogue.node("anica", anica_text, catalog.anica_choices[:], anica_speaker),
        dialogue.node("anica-water", anica_water_close, catalog.anica_close_choices[:], anica_speaker),
        dialogue.node("anica-sea", anica_sea_close, catalog.anica_close_choices[:], anica_speaker),
        dialogue.node("anica-repeat-water", anica_repeat_water_close, catalog.anica_close_choices[:], anica_speaker),
        dialogue.node("anica-repeat-bed", anica_repeat_bed_close, catalog.anica_close_choices[:], anica_speaker),
    }
    catalog.anica = {
        id    = "anica",
        nodes = catalog.anica_nodes[:],
    }

    catalog.toma_choices = {
        dialogue.choice("Give Toma the east-island post.", 2, has_post_for_toma, complete_toma_delivery),
        dialogue.choice("I'll carry the island post to Lena.", 1, can_begin_repeat_eastbound, accept_post_delivery),
        dialogue.choice("I'll return when the postbag is ready."),
    }
    catalog.toma_handoff_choices = {
        dialogue.choice("I'll follow the ledger exactly.", 5, effect = choose_orderly_cargo),
        dialogue.choice("I'll improvise if the sea does.", 6, effect = choose_expressive_cargo),
    }
    catalog.toma_handoff_close_choices[0] = dialogue.choice("Eastbound, then.")
    catalog.toma_receipt_choices = {
        dialogue.choice("Everything stayed in its proper place.", 3),
        dialogue.choice("The supper note outranked the glass.", 4),
    }
    catalog.toma_close_choices[0] = dialogue.choice("Your ledger is safe with me.")
    catalog.toma_nodes = {
        dialogue.node(
            "toma",
            toma_text,
            catalog.toma_choices[:],
            proc(_: ^dialogue.Context) -> string { return "TOMA · POSTMASTER" },
        ),
        dialogue.node(
            "toma-handoff",
            toma_post_handoff_text,
            catalog.toma_handoff_choices[:],
            proc(_: ^dialogue.Context) -> string { return "TOMA · POSTMASTER" },
        ),
        dialogue.node(
            "toma-receipt",
            toma_post_receipt_text,
            catalog.toma_receipt_choices[:],
            proc(_: ^dialogue.Context) -> string { return "TOMA · POSTMASTER" },
        ),
        dialogue.node(
            "toma-orderly",
            toma_post_orderly_close,
            catalog.toma_close_choices[:],
            proc(_: ^dialogue.Context) -> string { return "TOMA · POSTMASTER" },
        ),
        dialogue.node(
            "toma-teasing",
            toma_post_teasing_close,
            catalog.toma_close_choices[:],
            proc(_: ^dialogue.Context) -> string { return "TOMA · POSTMASTER" },
        ),
        dialogue.node(
            "toma-handoff-orderly",
            toma_post_handoff_orderly_close,
            catalog.toma_handoff_close_choices[:],
            proc(_: ^dialogue.Context) -> string { return "TOMA · POSTMASTER" },
        ),
        dialogue.node(
            "toma-handoff-improvise",
            toma_post_handoff_improvise_close,
            catalog.toma_handoff_close_choices[:],
            proc(_: ^dialogue.Context) -> string { return "TOMA · POSTMASTER" },
        ),
    }
    catalog.toma = {
        id    = "toma",
        nodes = catalog.toma_nodes[:],
    }

    catalog.lena_choices = {
        dialogue.choice("Give Lena the west-island post.", 2, has_post_for_lena, complete_lena_delivery),
        dialogue.choice("I'll carry the island post to Toma.", 1, can_begin_repeat_westbound, accept_post_delivery),
        dialogue.choice("I'll let you finish sorting."),
    }
    catalog.lena_handoff_choices = {
        dialogue.choice("I'll keep Toma's post in order.", 5, effect = choose_orderly_cargo),
        dialogue.choice("I'll make sure he reads SUPPER first.", 6, effect = choose_expressive_cargo),
    }
    catalog.lena_handoff_close_choices[0] = dialogue.choice("Westbound, then.")
    catalog.lena_receipt_choices = {
        dialogue.choice("Everything stayed dry and flat.", 3),
        dialogue.choice("Toma supervised every item personally.", 4),
    }
    catalog.lena_close_choices[0] = dialogue.choice("I'll leave the filing to you.")
    catalog.lena_nodes = {
        dialogue.node(
            "lena",
            lena_text,
            catalog.lena_choices[:],
            proc(_: ^dialogue.Context) -> string { return "LENA · POSTMASTER" },
        ),
        dialogue.node(
            "lena-handoff",
            lena_post_handoff_text,
            catalog.lena_handoff_choices[:],
            proc(_: ^dialogue.Context) -> string { return "LENA · POSTMASTER" },
        ),
        dialogue.node(
            "lena-receipt",
            lena_post_receipt_text,
            catalog.lena_receipt_choices[:],
            proc(_: ^dialogue.Context) -> string { return "LENA · POSTMASTER" },
        ),
        dialogue.node(
            "lena-orderly",
            lena_post_orderly_close,
            catalog.lena_close_choices[:],
            proc(_: ^dialogue.Context) -> string { return "LENA · POSTMASTER" },
        ),
        dialogue.node(
            "lena-teasing",
            lena_post_teasing_close,
            catalog.lena_close_choices[:],
            proc(_: ^dialogue.Context) -> string { return "LENA · POSTMASTER" },
        ),
        dialogue.node(
            "lena-handoff-orderly",
            lena_post_handoff_orderly_close,
            catalog.lena_handoff_close_choices[:],
            proc(_: ^dialogue.Context) -> string { return "LENA · POSTMASTER" },
        ),
        dialogue.node(
            "lena-handoff-supper",
            lena_post_handoff_supper_close,
            catalog.lena_handoff_close_choices[:],
            proc(_: ^dialogue.Context) -> string { return "LENA · POSTMASTER" },
        ),
    }
    catalog.lena = {
        id    = "lena",
        nodes = catalog.lena_nodes[:],
    }
}
