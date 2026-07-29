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
    }
    return {}, false
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

magneto_memory_text :: proc(resident: Resident) -> string {
    switch resident {
    case .Marta:
        return "The replacement magneto starts before my coffee now. Gerta calls this proof she was right; io call it proof the old one deserved retirement with honors."
    case .Gerta:
        return "Marta reports the replacement magneto starts first pull. She says this proves her maintenance was correct. Curiously, it also proves my replacement was correct."
    case .Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena:
        return ""
    }
    return ""
}

magneto_opinion_text :: proc(resident, favored_sister: Resident) -> string {
    switch resident {
    case .Marta:
        if favored_sister == .Marta {
            return "Esatto. Two extra summers from one cracked magneto is not stubbornness; it is careful retirement planning. Tell Gerta slowly."
        }
        return "Also true. Gerta found the right replacement before I admitted needing it. Una sister may be correct without receiving a parade."
    case .Gerta:
        if favored_sister == .Marta {
            return "Fair. Marta heard the crack before any instrument did and kept it safe until replacement. I shall concede this in very small handwriting."
        }
        return "Ja. Correct series, correct timing, dry delivery. But if Marta asks, say only that la machine made an independent decision."
    case .Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena:
        return ""
    }
    return ""
}

magneto_accept_careful_text :: proc() -> string {
    return "Bene. Oilcloth around il metal, knot away from the terminals, und broken magneto above the spray. Gerta appreciates correct nouns."
}

magneto_accept_inspection_text :: proc() -> string {
    return "Only couriers with wet socks. Arrive asciutto, say 'broken magneto' before any story, et she may inspect merely your knot."
}

magneto_handoff_crack_text :: proc() -> string {
    return "Ja. Under clean oil, la crack runs farther than it confessed. Same series, correct replacement, und no more borrowed summers."
}

magneto_handoff_marta_text :: proc() -> string {
    return "Long enough to prove she heard la machine correctly. Marta calls it maintenance; io call it affection with a torque wrench."
}

magneto_return_dry_text :: proc() -> string {
    return "Perfetto. Dry coils, clean terminals, und zero salt. Gerta may distrust couriers, but she packs for their success."
}

magneto_return_knot_text :: proc() -> string {
    return "Of course. Due turns, one square knot, et a tail long enough to criticize. My sister writes instructions even in string."
}

airfield_news_warm_text :: proc(resident: Resident) -> string {
    switch resident {
    case .Marta:
        return "Piano is good. Una lighthouse, un forno, und persone all punish haste—only the repair manual admits it."
    case .Gerta:
        return "Ja. Niko plans con flour, Iva mit meteo; between them, una crossing becomes practical."
    case .Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena:
        return ""
    }
    return ""
}

airfield_news_discreet_text :: proc(resident: Resident) -> string {
    switch resident {
    case .Marta:
        return "Every runway, quai, und cucina has witnesses. Fortunately, ciascuno is busy pretending otherwise."
    case .Gerta:
        return "Small islands, lange sightlines, et zero true secrets. Privacy survives because everyone misplaces one fact."
    case .Niko, .Iva, .Bojan, .Zora, .Vesna, .Petar, .Anica, .Toma, .Lena:
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
    if state == nil || state.clinic_visits == 0 {
        return "La clinica is quiet, dobro. Mais we keep one letto ready, perché pilots confuse fortuna with meteo."
    }
    if state.clinic_visits == 1 {
        return "No bones broken. Un poco de repos, beaucoup acqua, und today zero bravura. Your glasses are on the tray."
    }
    switch state.clinic_visits % 3 {
    case 0:
        return fmt.tprintf(
            "Visit numero %d. You know la routine: acqua, repos, then inspect il meteo before the motor.",
            state.clinic_visits,
        )
    case 1:
        return fmt.tprintf(
            "Visit numero %d. La tray remembered your glasses; io prefer when patients learn faster than furniture. Acqua, repos, meteo.",
            state.clinic_visits,
        )
    case 2:
        return fmt.tprintf(
            "Visit numero %d. Same pilot, new bruise, und familiar glasses. Bene: acqua first; then we compare your story with il meteo.",
            state.clinic_visits,
        )
    }
    return ""
}

vesna_care_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.clinic_visits > 1 {
        return "Dobro. On visit two, wisdom is still cheaper than bandages. Acqua first, meteo second, aeroplano last."
    }
    return "Good. Bravura is expensive medicine, und the clinica never keeps it in stock. Acqua first; meteo before the motor."
}

vesna_joke_close :: proc(_: ^dialogue.Context) -> string {
    return "From above, perhaps. From this letto, the landing arrived con excellent clarity. Keep the joke; lose the repeat visit."
}

vesna_repeat_honest_close :: proc(_: ^dialogue.Context) -> string {
    return "Then we improve one variable, non invent una heroic cause. You checked il meteo; next we inspect speed, fuel, und judgment."
}

vesna_repeat_memory_close :: proc(_: ^dialogue.Context) -> string {
    return "Excellent: repetition has produced memory. Now let memory produce caution, così I may keep your glasses off this tray."
}

petar_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.clinic_visits == 0 {
        return "Io wash the clinic linens ogni morning. Das is not an invitation to occupy le letto, capito?"
    }
    if state.clinic_visits == 1 {
        return(
            "Your glasses are on the tray, la scarf is dry, und your aeroplano waits at the airfield. In questo order." \
        )
    }
    switch state.clinic_visits % 3 {
    case 0:
        return fmt.tprintf(
            "Visit numero %d. Your glasses found la tray without assistance. I wish il pilot showed equal navigation.",
            state.clinic_visits,
        )
    case 1:
        return fmt.tprintf(
            "Visit numero %d. Una dry scarf, due clean sheets, und zero applause. Vesna handles medicine; io protect the linens.",
            state.clinic_visits,
        )
    case 2:
        return fmt.tprintf(
            "Visit numero %d. La scarf is dry, the door remains innocent, und your aeroplano waits outside. In questo order.",
            state.clinic_visits,
        )
    }
    return ""
}

petar_door_close :: proc(_: ^dialogue.Context) -> string {
    return "The door has a handle, una sign, und zero propeller. An excellent machine. Vesna recommends you use it slowly."
}

petar_window_close :: proc(_: ^dialogue.Context) -> string {
    return "Closer, da. Also closed. Next time choose la door before I choose which wet linen becomes your new scarf."
}

petar_repeat_door_close :: proc(_: ^dialogue.Context) -> string {
    return "Then la door maintains its perfect safety record. I shall inform Vesna one piece of clinic equipment escaped involvement."
}

petar_repeat_linens_close :: proc(_: ^dialogue.Context) -> string {
    return "They do. Questa sheet requested transfer to la lighthouse. I denied it; even linen must finish the shift."
}

anica_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.clinic_visits == 0 {
        return(
            "The east clinica faces il mare. Dobro for finding boats; less dobro when an aeroplano arrives without appointment." \
        )
    }
    if state.clinic_visits == 1 {
        return(
            "Respira piano. Nothing cassé, solo one grande rumore. Acqua here und meteo there—choose acqua first." \
        )
    }
    switch state.clinic_visits % 3 {
    case 0:
        return fmt.tprintf(
            "Again you, visit numero %d. Il mare pardons beaucoup, but it does not keep my records.",
            state.clinic_visits,
        )
    case 1:
        return fmt.tprintf(
            "Visit numero %d. Acqua waits by the bed, meteo waits on the wall, und il mare waits for nobody. Choose the first.",
            state.clinic_visits,
        )
    case 2:
        return fmt.tprintf(
            "Again, numero %d. I moved the acqua closer and la appointment book farther away. One of us is learning.",
            state.clinic_visits,
        )
    }
    return ""
}

anica_water_close :: proc(_: ^dialogue.Context) -> string {
    return "Exactly. Acqua first, then meteo, then decisions. The order is small enough to remember even after una grande rumore."
}

anica_sea_close :: proc(_: ^dialogue.Context) -> string {
    return "Il mare counts boats, non glasses. Drink this one; I shall record it where the tide cannot edit."
}

anica_repeat_water_close :: proc(_: ^dialogue.Context) -> string {
    return "You remembered acqua. Bene—one less instruction between il rumore and good sense. Drink; then we discuss the rest."
}

anica_repeat_bed_close :: proc(_: ^dialogue.Context) -> string {
    return "No reservations. Mais I have moved your glass to the same shelf twice. That is hospitality enough; do not make it tradition."
}

toma_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil {
        return "West-island posta, dobro. Every traversata conta, even quand the postbag is light."
    }
    post_cycle := state.repeat_deliveries / 2 % 3
    if state.delivery.active && state.delivery.to == .Toma {
        switch post_cycle {
        case 0:
            return "Ah, the east-island post. Lamp glass below, Lena's dinner note above, und pane separate. She packs correctly; naturally, io taught her."
        case 1:
            return "The east-island post, dobro. Lena wrapped each lamp glass in my old weather reports. Enfin, one accurate use for them."
        case 2:
            return "Post from Lena. She writes 'eat before sorting' on the outside, così even a postmaster cannot misfile it."
        }
    }
    if !state.delivery.active && state.repeat_deliveries % 2 == 0 {
        switch post_cycle {
        case 0:
            return "Lena expects this island post: pane, postcards, et one pressed flower. Carry it east before the pane becomes stone."
        case 1:
            return "Island post for Lena: two postcards, fresh pane, und her blue pencil. She says I borrowed it. The records say nothing."
        case 2:
            return "Lena's island post: pane on top, postcards flat, et one basil cutting. Tell her it survived my supervision."
        }
    }
    switch post_cycle {
    case 0:
        return "The postbag repose, mais io non. Every letter finds its place before la bura enters the door."
    case 1:
        return "No island post yet. Lena would call this shelf crooked; from her island, perhaps it appears straight."
    case 2:
        return "Postbag empty, ledger balanced, pane hidden from gulls. A rare administrative triumph."
    }
    return ""
}

lena_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil {
        return "East-island posta: letters above, lamp glass below, und pane always visible."
    }
    post_cycle := state.repeat_deliveries / 2 % 3
    if state.delivery.active && state.delivery.to == .Lena {
        switch post_cycle {
        case 0:
            return "The west-island post est arrivé, dobro. Pane here, postcards là, und the flower—delicato, it has traveled enough."
        case 1:
            return "My blue pencil, enfin. Toma calls this returning; the bite marks call it una confession."
        case 2:
            return "Pane, postcards, et basil. Toma packed the roots in a customs form—official soil, apparently."
        }
    }
    if !state.delivery.active && state.repeat_deliveries % 2 == 1 {
        switch post_cycle {
        case 0:
            return "Toma expects this island post: lamp glass, bien protected, et a dinner note. Carry it west; glass cannot swim."
        case 1:
            return "Island post for Toma: lamp glass, his weather reports, et one note marked SUPPER. Keep that word visible."
        case 2:
            return "Toma's island post: lamp glass below, dinner note above, und no basil. He must first prove he watered the last one."
        }
    }
    switch post_cycle {
    case 0:
        return "Everything est sorted, quasi. The letters wait calmly; solo il pane pretends to be urgent."
    case 1:
        return "No island post today. I am enjoying temporary custody of all my pencils."
    case 2:
        return "The shelves are quiet. Toma would distrust this, donc I shall mention nothing."
    }
    return ""
}

toma_post_handoff_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Island post for Lena, eastbound. Keep la postbag dry and il pane visible."
    switch state.repeat_deliveries / 2 % 3 {
    case 0:
        return "Island post for Lena, eastbound: pane on top, postcards flat, flower away from elbows. La postbag knows the route; remind the gulls."
    case 1:
        return "Lena's island post, with her blue pencil inside. Keep la postbag dry—and if she asks, the bite marks predate my administration."
    case 2:
        return "Eastbound island post: pane, postcards, basil upright. If la cutting leans, tell Lena the vento voted."
    }
    return ""
}

lena_post_handoff_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Island post for Toma, westbound. Lamp glass below, dinner note above."
    switch state.repeat_deliveries / 2 % 3 {
    case 0:
        return "Island post for Toma, westbound: lamp glass below, dinner note above. Keep SUPPER visible; he respects capital letters."
    case 1:
        return "Toma's island post. His weather reports protect la lamp glass now, which is the safest forecast they have made."
    case 2:
        return "Westbound island post: lamp glass, dinner note, zero basil. Do not add sympathy; Toma can water that himself."
    }
    return ""
}

toma_post_handoff_orderly_close :: proc(_: ^dialogue.Context) -> string {
    return "Dobro. Keep pane alto, postcards flat, und la flower sheltered. Exactness is simply kindness with numbered lines."
}

toma_post_handoff_improvise_close :: proc(_: ^dialogue.Context) -> string {
    return "Acceptable. Il mare may amend the route, mais not la postbag. Protect Lena's things; blame les gulls only with evidence."
}

lena_post_handoff_orderly_close :: proc(_: ^dialogue.Context) -> string {
    return "Bien. Lamp glass below, note above, und zero heroics between. Order is how fragile cose arrive without speeches."
}

lena_post_handoff_supper_close :: proc(_: ^dialogue.Context) -> string {
    return "Enfin, a courier who understands priority. If Toma protests, remind him la capital letters outrank his ledger."
}

toma_post_receipt_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.repeat_deliveries == 0 {
        return "La postbag arrived dry. Lamp glass below, note above—Lena will permit us both to remain employed."
    }
    switch (state.repeat_deliveries - 1) / 2 % 3 {
    case 0:
        return "Lamp glass whole, dinner note legible, pane wisely separate. Lena underlined SUPPER twice; this is no longer correspondence, it is navigation."
    case 1:
        return "Lamp glass whole, old weather reports returned. Lena marked every wrong forecast in blue pencil—molto educational, completely vindictive."
    case 2:
        return "Lamp glass whole, dinner note on top, zero basil. She drew a watering can beside my name. Subtlety has left la posta."
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
        return "I observed. Dry corners, straight stack, niente crushed. A postmaster notices care even when the ledger has no column for it."
    case 1:
        return "I observed. Weather reports flat, lamp glass whole, und no blue-pencil correction added en route. Excellent restraint."
    case 2:
        return "I observed. Glass below, note above, zero unauthorized basil. Even la watering-can accusation arrived unbent."
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
        return "Officially, la lamp glass had priority. Unofficially, I read SUPPER before checking the crack. Do not revise the ledger."
    case 1:
        return "Lena returned every forecast con evidence. I inspected la blue pencil first—professional curiosity, naturellement."
    case 2:
        return "The watering can was very clear. La lamp glass merely confirmed the parcel survived while my reputation did not."
    }
    return ""
}

lena_post_receipt_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.repeat_deliveries == 0 {
        return "La postbag arrived dry. Pane visible, postcards flat—Toma has remembered at least the important civilization."
    }
    switch (state.repeat_deliveries - 1) / 2 % 3 {
    case 0:
        return "Pane still soft, postcards flat, pressed flower intact. Toma put it inside a customs declaration; apparently tenderness now requires paperwork."
    case 1:
        return "My blue pencil, enfin—plus pane and two postcards as witnesses. The bite marks have crossed il mare but not escaped justice."
    case 2:
        return "Pane, postcards, et one living basil cutting. Toma packed the roots in official soil and added three watering instructions for himself."
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
        return "I observed. Dry paper, soft pane, every corner respected. Care is the one postal mark nobody can counterfeit."
    case 1:
        return "I observed. Blue pencil dry, pane soft, postcards square. Even Toma's bite marks arrived exactly where recorded."
    case 2:
        return "I observed. Basil upright, roots damp, customs form absurdly flat. Care can survive bureaucracy, apparently."
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
        return "Naturalmente. Toma supervises with both hands, then writes a form saying the parcel arranged itself. I shall file your testimony."
    case 1:
        return "Personally, yes. He wrapped la pencil like crown jewels, puis denied every tooth mark in triplicate."
    case 2:
        return "Toma supervised the basil until it acquired paperwork. I shall water la plant and archive his anxiety."
    }
    return ""
}

zora_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.tarot_readings == 0 {
        return(
            "Close la shutter, piccolo courier. The bura already mixes enough. Le cards do not command il mare; they show only where the vento turns." \
        )
    }
    if state.tarot_last_moment == tarot_moment(state) {
        return "Le cards have spoken for questo vento. Now inspect the real cielo; return when something changes."
    }
    return "Sit. The vento has turned since l'ultima reading; let us see if le cards noticed."
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
        return "deux persone must choose la stessa traversata"
    case id == 7:
        return "the voyage demande steady hands, non speed"
    case id == 9:
        return "una lamp solitaria can still guide someone"
    case id == 10:
        return "the wheel turns, mais only if someone gives it a push"
    case id == 16:
        return "what looks like ruin demande first an inspection"
    case id == 17:
        return "una distant light is aussi one promise"
    case id == 18:
        return "the meteo hides half of la route"
    case id == 19:
        return "clarity will arrive con il daylight"
    case id >= 22 && id < 36:
        return "work et courage pull in la stessa direction"
    case id >= 36 && id < 50:
        return "affection travels better in un container simple"
    case id >= 50 && id < 64:
        return "one parola cuts; una precise parola repairs"
    case id >= 64:
        return "the concrete thing under your hand merita confidence"
    }
    return "change has already entered through la window"
}

zora_story_omen :: proc(state: ^State) -> string {
    if state == nil do return "Do not chase il symbol; watch what it moves."
    switch state.romance {
    case .Unintroduced:
        return "Deux persone keep the same hours on different shores. They do not call it waiting yet."
    case .First_Letter:
        return "Una sealed letter crosses il mare best in hands that stay silent."
    case .Corresponding:
        return "La distance becomes small first on paper, then sotto the feet."
    case .Invitation:
        if state.repair != .Repaired {
            return "Canvas, vento, et one voyage need repair before making a promise."
        }
        return "La route in the cielo is ready. Il courage needs only to board."
    case .Meeting:
        return "Deux chairs under una blue awning make less shadow than one empty chair."
    case .Together:
        return "You know la route: pane outbound, lamp glass protected on return."
    }
    return ""
}

zora_reading_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.tarot_layout.count == 0 do return "La table is empty; something has eaten la fortuna."
    first := state.tarot_layout.placements[0]
    direction := first.orientation == .Reversed ? "controvento" : "con il vento"
    switch state.tarot_layout.spread {
    case .Single:
        return fmt.tprintf(
            "%s, %s.",
            tarot.card_name(first.card),
            direction,
        )
    case .Three_Card:
        second := state.tarot_layout.placements[1]
        third := state.tarot_layout.placements[2]
        return fmt.tprintf(
            "Past: %s.\nNow: %s.\nPossible shore: %s.",
            tarot.card_name(first.card),
            tarot.card_name(second.card),
            tarot.card_name(third.card),
        )
    case .Celtic_Cross:
        crossing := state.tarot_layout.placements[1]
        shore := state.tarot_layout.placements[state.tarot_layout.count - 1]
        return fmt.tprintf(
            "Core: %s.\nCrossing: %s.\nFar shore: %s.",
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
        "The first card says %s.\nFor you, oggi: %s",
        tarot_card_omen(first.card),
        zora_story_omen(state),
    )
}

zora_recall_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil || state.tarot_layout.count == 0 do return "Without una card on the table, memory becomes theatre."
    first := state.tarot_layout.placements[0]
    direction := first.orientation == .Reversed ? "controvento" : "con il vento"
    return fmt.tprintf(
        "%s was first, %s. Same card, same vento.\nRemember: %s",
        tarot.card_name(first.card),
        direction,
        zora_story_omen(state),
    )
}

zora_recall_act_close :: proc(_: ^dialogue.Context) -> string {
    return "Bene. A card that keeps you at la table has failed. Close la shutter behind you; il mondo is waiting."
}

zora_recall_sky_close :: proc(_: ^dialogue.Context) -> string {
    return "As you should. Il cielo changes openly; le cards whisper after. Take both seriously, worship neither."
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
    if state == nil do return "Buongiorno. Les ovens will be hot avant il porto wakes."
    if state.delivery.active && state.delivery.to == .Niko {
        switch state.delivery.kind {
        case .First_Reply:
            return "Ah, you are back across il mare. Tu have Iva's reply con te?"
        case .Regatta_Acceptance:
            return "Bojan's motor crossed la bay at alba. Is that Iva's regatta acceptance?"
        case .Repeat_Westbound:
            return "Lamp glass travels malissimo. I hope Iva packed it better than moi."
        case .None, .First_Letter, .Regatta_Invitation, .Repeat_Eastbound:
        }
    }
    switch state.romance {
    case .Unintroduced:
        if state.airfield_errand == .Eastbound || state.airfield_errand == .Completed {
            return "When you return east… io have una sealed letter for Iva. The envelope is piccola outside, at least."
        }
        return "La lamp on the east island blinks twice avant alba. Iva watches while my ovens warm."
    case .First_Letter:
        return "La cardamom box looks molto suspicious when someone waits for risposta."
    case .Corresponding:
        return "La regatta needs un baker, certo. Questa regatta invitation is for Iva, keeper du phare."
    case .Invitation:
        return "There is una blue awning on the quay. Nobody knows why io inspect it always."
    case .Meeting:
        return "Iva found the blue awning. It seems smaller con two persone under it."
    case .Together:
        return "The island post continua: Iva says lamp glass can wait. Das pane cannot."
    }
    return ""
}

niko_delivery_reaction :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return ""
    switch state.delivery.kind {
    case .First_Reply:
        return "She remembered la farina from my first note. Non the part I expected."
    case .Regatta_Acceptance:
        return "Elle is coming. I must make la tenda look as if io did not polish it."
    case .Repeat_Westbound:
        return "Lamp glass survived, und elle included instructions per cena. One of them is more fragile."
    case .None, .First_Letter, .Regatta_Invitation, .Repeat_Eastbound:
        return "Grazie. Some cose arrive better when nobody opens them en route."
    }
    return ""
}

niko_handoff_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Keep la letter sealed and above the spray. Iva will understand the rest."
    switch state.delivery.kind {
    case .First_Letter:
        return "Here: una sealed letter for Iva, wrapped beside the cardamom recipe. Keep it above il spray; the ink has less courage than you."
    case .Regatta_Invitation:
        return "This regatta invitation is for Iva. La blue awning is written only once, so perhaps she will think io mention it casually."
    case .Repeat_Eastbound:
        switch state.repeat_deliveries / 2 % 3 {
        case 0:
            return "For Iva: warm pane, postcards, und one pressed flower. Keep la package above the spray; sentiment has poor waterproofing."
        case 1:
            return "For Iva: pane, her blue measuring spoon, et cardamom. The spoon is wrapped; my explanation is not."
        case 2:
            return "For Iva: pane and una basil cutting. Keep la roots upright; encouragement may be added in moderation."
        }
    case .None, .First_Reply, .Regatta_Acceptance, .Repeat_Westbound:
        return "Keep la letter sealed and above the spray. Iva will understand the rest."
    }
    return ""
}

niko_handoff_careful_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.delivery.kind == .Repeat_Eastbound {
        return "Grazie. Pane on top, postcards flat, flower sheltered. La package can survive il mare without becoming a story."
    }
    return "Grazie. Il mare may read every shoreline, mais not this letter. Keep Iva's name dry; the rest can arrive wrinkled."
}

niko_handoff_playful_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.delivery.kind == .Repeat_Eastbound {
        return "Naturally. Una flower, warm pane, und zero personal evidence. Iva may classify them differently."
    }
    return "There is no evidence. Solo cardamom, una sealed letter, und a baker who cleaned flour from one sleeve. Completely routine."
}

niko_together_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Iva says la lighthouse clock gains one minute. My oven clock disagrees, loudly."
    switch state.repeat_deliveries / 2 % 3 {
    case 0:
        return "Iva says la lighthouse clock gains one minute. My oven clock loses two. Between us, dinner arrives exactly on time."
    case 1:
        return "She returned my blue measuring spoon inside three layers of lamp paper. Très safe, completely unnecessary, unmistakably Iva."
    case 2:
        return "Iva says basil needs acqua, non encouragement. Io provide both; the plant has not declared a preference."
    }
    return ""
}

niko_together_rhythm_close :: proc(_: ^dialogue.Context) -> string {
    return "Una rhythm, sì: lamp, oven, postbag, supper. Nothing romantic—solo excellent scheduling with cardamom."
}

niko_together_experiment_close :: proc(_: ^dialogue.Context) -> string {
    return "Write successful in large letters, per favore. Iva files small print beside maintenance complaints."
}

niko_warm_close :: proc(_: ^dialogue.Context) -> string {
    return "Va bene. Io place another tray inside; waiting goes better con useful work."
}

niko_discreet_close :: proc(_: ^dialogue.Context) -> string {
    return "Bene. Una sealed letter deserves at least one persona who keeps silent."
}

meeting_iva_text :: proc(_: ^dialogue.Context) -> string {
    return "The blue awning is exactly where Niko described it. Bojan calls il volo routine, mais routine landings use tutte three wheels, sì?"
}

meeting_niko_warm :: proc(_: ^dialogue.Context) -> string {
    return "The third wheel was decorative. Siediti, per favore; io made enough pane pour una regatta and one delayed aeroplano."
}

meeting_niko_discreet :: proc(_: ^dialogue.Context) -> string {
    return "Then you saw nothing, grazie. Only un baker, una lighthouse keeper, und lunch beneath an ordinary awning."
}

meeting_iva_warm_close :: proc(_: ^dialogue.Context) -> string {
    return "He counted il pane twice und les minutes three times. I arrived before either ran out."
}

meeting_iva_discreet_close :: proc(_: ^dialogue.Context) -> string {
    return "A very ordinary awning. Niko polished la frame ieri—due times, mit complete indifference."
}

iva_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Dobro jutro. La lamp is ready; il meteo is not yet."
    if state.delivery.active && state.delivery.to == .Iva {
        switch state.delivery.kind {
        case .First_Letter:
            return "Una sealed letter crossed all that blue mare to find this lighthouse."
        case .Regatta_Invitation:
            return "Niko's regatta invitation becomes straighter when he pretends to be non nervous."
        case .Repeat_Eastbound:
            return "The island post smells as if Niko confused la postal route con una pantry."
        case .None, .First_Reply, .Regatta_Acceptance, .Repeat_Westbound:
        }
    }
    switch state.romance {
    case .Unintroduced:
        return "Due flashes signal clear acqua. One always looked un poco solo."
    case .First_Letter:
        return "He remembered il cardamom. Bene, the lighthouse can offer Iva's reply."
    case .Corresponding:
        return "La west-island posta has become remarkably punctual."
    case .Invitation:
        if state.repair == .Repaired {
            return(
                "Tu repaired Bojan's aeroplano before io needed it. Grazie; now you can carry la regatta acceptance." \
            )
        }
        return "Io can respond to Niko, but la broken wing cannot carry me. Nema regatta yet."
    case .Meeting:
        return "The west island is more noisy than le phare. Niko, fortunately, non."
    case .Together:
        return "The island post brings pane, as if il mare were a problem that feeding always solves."
    }
    return ""
}

iva_delivery_reaction :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return ""
    switch state.delivery.kind {
    case .First_Letter:
        return "He remembered il cardamom. Tell Niko: due flashes, because one felt solo."
    case .Regatta_Invitation:
        if state.repair == .Repaired {
            return "Bojan's aeroplano is ready. Grazie; your earlier kindness arranged ma risposta."
        }
        return "Io would go, mais Bojan's aeroplano shows more cielo through la wing than above it."
    case .Repeat_Eastbound:
        return "Pane, postcards, und one flower. He packed tre kinds of meteo."
    case .None, .First_Reply, .Regatta_Acceptance, .Repeat_Westbound:
        return "Still sealed. Grazie for treating la crossing as part of the promise."
    }
    return ""
}

iva_handoff_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Keep ma risposta sealed until Niko opens it on the other shore."
    switch state.delivery.kind {
    case .First_Reply:
        return "My reply for Niko. It says due flashes, among other things. Keep ma risposta sealed until the west island."
    case .Regatta_Acceptance:
        return "My regatta acceptance for Niko. The blue awning is sufficient; no need for him to construct una second awning from worry."
    case .Repeat_Westbound:
        switch (state.repeat_deliveries - 1) / 2 % 3 {
        case 0:
            return "For Niko: lamp glass below, dinner note above. Keep la package dry; only one item survives being read in rain."
        case 1:
            return "For Niko: lamp paper, his blue spoon, und a meteo note. He will dispute the forecast after returning the spoon."
        case 2:
            return "For Niko: basil instructions, lamp glass, et one dinner note. The plant needs acqua; Niko needs underlining."
        }
    case .None, .First_Letter, .Regatta_Invitation, .Repeat_Eastbound:
        return "Keep ma risposta sealed until Niko opens it on the other shore."
    }
    return ""
}

iva_handoff_careful_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.delivery.kind == .Repeat_Westbound {
        return "Dobro. Lamp glass below, note above, und dry corners. Niko may improvise dinner only after la package arrives."
    }
    return "Dobro. Una seal is a small lighthouse: it says where la message belongs, et where curious hands do not."
}

iva_handoff_lights_close :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state != nil && state.delivery.kind == .Repeat_Westbound {
        return "Follow them exactly enough to blame me. La glass is fragile; il dinner note only pretends to be."
    }
    return "Due flashes, then west. If il meteo argues, trust la compass first; poetry is terrible navigation but good company."
}

iva_together_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "Niko believes every lighthouse problem can be reduced by one warm loaf."
    switch state.repeat_deliveries / 2 % 3 {
    case 0:
        return "Niko believes every lighthouse problem can be reduced by one warm loaf. The evidence is annoyingly favorable."
    case 1:
        return "The west island remains noisy. But Niko has learned when silence means tea, und when it means more cardamom."
    case 2:
        return "He labels each basil pot con the date and a heroic title. I water them; history may decide who is responsible."
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
    return "Do not smile così at the lighthouse. Das encourages les gulls."
}

iva_discreet_close :: proc(_: ^dialogue.Context) -> string {
    return "Grazie. Le islands are already small without letters becoming public roads."
}

bojan_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "L'aeroplano und io are resting. Tutto tranquillo, more or less."
    switch state.repair {
    case .Not_Seen:
        return "La landing was perfekt. The ground arrived troppo early. You saw zero complication."
    case .Crash_Reported:
        return "Now la official version is brief; we can inspect the wing honestly."
    case .Diagnosed:
        return "One canvas panel is torn. Io have the canvas patch; tu have steadier hands than my reputation."
    case .Patched:
        return "Canvas patch tendu, wing ribs straight, controles libres. Voilà: turn the propeller, con prudenza."
    case .Repaired:
        if state.romance == .Invitation {
            return "L'aereo is ready for Iva. Io even cleaned the seat that is not mine."
        }
        return "Patch tensioned, wing ribs straight, controles free. Basta—that is notre engineering."
    }
    return ""
}

bojan_report_reaction :: proc(_: ^dialogue.Context) -> string {
    return "Then la official report is simple: pilot intact, pride under repair. Vieni—inspect the wing, where il canvas caught the ground."
}

bojan_inspect_reaction :: proc(_: ^dialogue.Context) -> string {
    return "There: one torn canvas panel, no broken rib. Hold la canvas patch to the light; if cielo shows through, we begin again."
}

bojan_inspect_practical_close :: proc(_: ^dialogue.Context) -> string {
    return "Esatto. Il rib keeps the wing's shape; la canvas keeps the wind from entering without a ticket. We repair only what failed."
}

bojan_inspect_teasing_close :: proc(_: ^dialogue.Context) -> string {
    return "A very expensive autograph. Fortunately, il ground signed only la canvas; my pride requires a separate estimate."
}

bojan_patch_reaction :: proc(_: ^dialogue.Context) -> string {
    return "Pull once along la seam—dobro. The patch stays flat, les controls move free, und now only the propeller may complain."
}

bojan_repair_reaction :: proc(_: ^dialogue.Context) -> string {
    return "Propeller turns, canvas holds, three wheels remain negotiable. Grazie—this aeroplano can carry more than my excuses."
}

bojan_repair_controls_close :: proc(_: ^dialogue.Context) -> string {
    return "They do. La patch stays flat, controles return to center, und the propeller complains evenly. Almost boring—perfetto."
}

bojan_repair_wheels_close :: proc(_: ^dialogue.Context) -> string {
    return "A temporary alliance. Tre wheels, one pilot, zero witnesses willing to certify the landing. We accept il miracle."
}

bojan_repaired_check_text :: proc(ctx: ^dialogue.Context) -> string {
    state := state_from_context(ctx)
    if state == nil do return "La canvas patch holds flat. One repair, many flights—that is a favorable argument."
    switch state.romance {
    case .Invitation:
        return "La canvas patch holds flat, controles move free, und Iva's seat is clean. Mechanically ready; socially, ask another engineer."
    case .Meeting:
        return "Iva arrived, la canvas patch stayed taut, et all three wheels participated. I have recorded two of these facts officially."
    case .Together:
        switch state.repeat_deliveries / 2 % 3 {
        case 0:
            return "La patch has crossed the bay twelve times. Canvas remembers good hands; il pilot merely borrows the credit."
        case 1:
            return "Iva marks every flight in a little meteo book. Beside my last landing she wrote: 'adequate, eventually.' Très scientific."
        case 2:
            return "Wing tension equal, controls libres, no daylight where canvas belongs. Even la bura has failed to improve our repair."
        }
    case .Unintroduced, .First_Letter, .Corresponding:
        return "La canvas patch holds flat. One repair, many flights—that is a favorable argument."
    }
    return ""
}

bojan_repaired_practical_close :: proc(_: ^dialogue.Context) -> string {
    return "See these pencil marks? Same distance today as dopo the repair. When they separate, we work. Until then, we fly."
}

bojan_repaired_teasing_close :: proc(_: ^dialogue.Context) -> string {
    return "Correct. La patch is quiet, dependable, et never describes the landing as 'perfekt.' I try not to resent canvas."
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
    niko_root_choices:      [9]dialogue.Choice,
    niko_reaction_choices:  [2]dialogue.Choice,
    niko_warm_choices:      [1]dialogue.Choice,
    niko_discreet_choices:  [1]dialogue.Choice,
    niko_handoff_choices:   [2]dialogue.Choice,
    niko_handoff_close_choices: [1]dialogue.Choice,
    niko_together_choices:  [2]dialogue.Choice,
    niko_together_close_choices: [1]dialogue.Choice,
    meeting_choices:        [2]dialogue.Choice,
    meeting_warm_choices:   [1]dialogue.Choice,
    meeting_discreet_choices: [1]dialogue.Choice,
    meeting_finish_choices: [1]dialogue.Choice,
    iva_root_choices:       [8]dialogue.Choice,
    iva_reaction_choices:   [2]dialogue.Choice,
    iva_warm_choices:       [1]dialogue.Choice,
    iva_discreet_choices:   [1]dialogue.Choice,
    iva_handoff_choices:    [2]dialogue.Choice,
    iva_handoff_close_choices: [1]dialogue.Choice,
    iva_together_choices:   [2]dialogue.Choice,
    iva_together_close_choices: [1]dialogue.Choice,
    bojan_choices:          [6]dialogue.Choice,
    bojan_report_choices:   [1]dialogue.Choice,
    bojan_inspect_choices:  [2]dialogue.Choice,
    bojan_inspect_close_choices: [1]dialogue.Choice,
    bojan_patch_choices:    [1]dialogue.Choice,
    bojan_repair_choices:   [2]dialogue.Choice,
    bojan_repair_close_choices: [1]dialogue.Choice,
    bojan_check_choices:    [2]dialogue.Choice,
    bojan_check_close_choices: [1]dialogue.Choice,
    zora_choices:           [5]dialogue.Choice,
    zora_reading_choices:   [2]dialogue.Choice,
    zora_counsel_choices:   [1]dialogue.Choice,
    zora_recall_choices:    [2]dialogue.Choice,
    zora_recall_close_choices: [1]dialogue.Choice,
    vesna_choices:          [4]dialogue.Choice,
    vesna_close_choices:    [1]dialogue.Choice,
    petar_choices:          [4]dialogue.Choice,
    petar_close_choices:    [1]dialogue.Choice,
    anica_choices:          [4]dialogue.Choice,
    anica_close_choices:    [1]dialogue.Choice,
    toma_choices:           [3]dialogue.Choice,
    toma_handoff_choices:   [2]dialogue.Choice,
    toma_handoff_close_choices: [1]dialogue.Choice,
    toma_receipt_choices:   [2]dialogue.Choice,
    toma_close_choices:     [1]dialogue.Choice,
    lena_choices:           [3]dialogue.Choice,
    lena_handoff_choices:   [2]dialogue.Choice,
    lena_handoff_close_choices: [1]dialogue.Choice,
    lena_receipt_choices:   [2]dialogue.Choice,
    lena_close_choices:     [1]dialogue.Choice,
    niko_nodes:             [15]dialogue.Node,
    iva_nodes:              [10]dialogue.Node,
    bojan_nodes:            [12]dialogue.Node,
    zora_nodes:             [6]dialogue.Node,
    vesna_nodes:            [5]dialogue.Node,
    petar_nodes:            [5]dialogue.Node,
    anica_nodes:            [5]dialogue.Node,
    toma_nodes:             [7]dialogue.Node,
    lena_nodes:             [7]dialogue.Node,
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
    catalog.meeting_warm_choices[0] =
        dialogue.choice("And enough bread for a delayed plane.", 7)
    catalog.meeting_discreet_choices[0] =
        dialogue.choice("I can forget the landing, not the bread.", 8)
    catalog.meeting_finish_choices[0] = dialogue.choice("Enjoy the regatta.", effect = finish_meeting)
    catalog.niko_handoff_choices = {
        dialogue.choice("I'll keep it dry and in order.", 13),
        dialogue.choice("I'll ignore any personal evidence.", 14),
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
        dialogue.node("meeting-niko-discreet", meeting_niko_discreet, catalog.meeting_discreet_choices[:], niko_speaker),
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
        dialogue.choice("I'll keep everything dry and intact.", 8),
        dialogue.choice("I'll follow your packing instructions.", 9),
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
        dialogue.node(
            "zora-recall-act",
            zora_recall_act_close,
            catalog.zora_recall_close_choices[:],
            zora_speaker,
        ),
        dialogue.node(
            "zora-recall-sky",
            zora_recall_sky_close,
            catalog.zora_recall_close_choices[:],
            zora_speaker,
        ),
    }
    catalog.zora = {
        id    = "zora",
        nodes = catalog.zora_nodes[:],
    }

    catalog.vesna_choices = {
        dialogue.choice("Thanks, doctor. I'll take it slower.", 1, clinic_is_first_visit),
        dialogue.choice("The landing looked softer from above.", 2, clinic_is_first_visit),
        dialogue.choice("I checked the weather. It wasn't enough.", 3, clinic_is_repeat_visit),
        dialogue.choice("I remembered where my glasses go.", 4, clinic_is_repeat_visit),
    }
    catalog.vesna_close_choices[0] = dialogue.choice("I'll check the weather first.")
    catalog.vesna_nodes = {
        dialogue.node("vesna", vesna_text, catalog.vesna_choices[:], vesna_speaker),
        dialogue.node("vesna-care", vesna_care_close, catalog.vesna_close_choices[:], vesna_speaker),
        dialogue.node("vesna-joke", vesna_joke_close, catalog.vesna_close_choices[:], vesna_speaker),
        dialogue.node(
            "vesna-repeat-honest",
            vesna_repeat_honest_close,
            catalog.vesna_close_choices[:],
            vesna_speaker,
        ),
        dialogue.node(
            "vesna-repeat-memory",
            vesna_repeat_memory_close,
            catalog.vesna_close_choices[:],
            vesna_speaker,
        ),
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
    }
    catalog.petar_close_choices[0] = dialogue.choice("I'll keep the linens out of it.")
    catalog.petar_nodes = {
        dialogue.node("petar", petar_text, catalog.petar_choices[:], petar_speaker),
        dialogue.node("petar-door", petar_door_close, catalog.petar_close_choices[:], petar_speaker),
        dialogue.node("petar-window", petar_window_close, catalog.petar_close_choices[:], petar_speaker),
        dialogue.node(
            "petar-repeat-door",
            petar_repeat_door_close,
            catalog.petar_close_choices[:],
            petar_speaker,
        ),
        dialogue.node(
            "petar-repeat-linens",
            petar_repeat_linens_close,
            catalog.petar_close_choices[:],
            petar_speaker,
        ),
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
    }
    catalog.anica_close_choices[0] = dialogue.choice("I'll make the next appointment quieter.")
    catalog.anica_nodes = {
        dialogue.node("anica", anica_text, catalog.anica_choices[:], anica_speaker),
        dialogue.node("anica-water", anica_water_close, catalog.anica_close_choices[:], anica_speaker),
        dialogue.node("anica-sea", anica_sea_close, catalog.anica_close_choices[:], anica_speaker),
        dialogue.node(
            "anica-repeat-water",
            anica_repeat_water_close,
            catalog.anica_close_choices[:],
            anica_speaker,
        ),
        dialogue.node(
            "anica-repeat-bed",
            anica_repeat_bed_close,
            catalog.anica_close_choices[:],
            anica_speaker,
        ),
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
        dialogue.choice("I'll follow the ledger exactly.", 5),
        dialogue.choice("I'll improvise if the sea does.", 6),
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
    catalog.toma = {id = "toma", nodes = catalog.toma_nodes[:]}

    catalog.lena_choices = {
        dialogue.choice("Give Lena the west-island post.", 2, has_post_for_lena, complete_lena_delivery),
        dialogue.choice("I'll carry the island post to Toma.", 1, can_begin_repeat_westbound, accept_post_delivery),
        dialogue.choice("I'll let you finish sorting."),
    }
    catalog.lena_handoff_choices = {
        dialogue.choice("I'll keep Toma's post in order.", 5),
        dialogue.choice("I'll make sure he reads SUPPER first.", 6),
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
    catalog.lena = {id = "lena", nodes = catalog.lena_nodes[:]}
}
