package story

import dialogue "../dialogue"

// A small two-island story campaign. The owning game decides where residents
// stand and how rewards are presented; this package owns narrative progression.

Island :: enum {
    West,
    East,
}

Resident :: enum {
    Marta,
    Niko,
    Iva,
    Bojan,
}

Romance_Stage :: enum {
    Unintroduced,
    First_Letter,
    Corresponding,
    Invitation,
    Together,
}

Repair_Stage :: enum {
    Not_Seen,
    Crash_Reported,
    Diagnosed,
    Patched,
    Repaired,
}

Delivery :: struct {
    active:      bool,
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
    has_tool_roll:        bool,
    has_wing_patch:       bool,
}

resident_name :: proc(resident: Resident) -> string {
    switch resident {
    case .Marta:
        return "Marta"
    case .Niko:
        return "Niko"
    case .Iva:
        return "Iva"
    case .Bojan:
        return "Bojan"
    }
    return ""
}

resident_island :: proc(resident: Resident) -> Island {
    switch resident {
    case .Iva:
        return .East
    case .Marta, .Niko, .Bojan:
        return .West
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
            from        = .Niko,
            to          = .Iva,
            origin      = .West,
            destination = .East,
            subject     = "A recipe for a clear morning",
        }
        state.romance = .First_Letter
    case .First_Letter:
        delivery = {
            active      = true,
            from        = .Iva,
            to          = .Niko,
            origin      = .East,
            destination = .West,
            subject     = "The lighthouse keeper's reply",
        }
        state.romance = .Corresponding
    case .Corresponding:
        delivery = {
            active      = true,
            from        = .Niko,
            to          = .Iva,
            origin      = .West,
            destination = .East,
            subject     = "An invitation for the regatta",
        }
        state.romance = .Invitation
    case .Invitation:
        // The invitation cannot conclude until Bojan's aircraft is airworthy.
        if state.repair != .Repaired do return false
        delivery = {
            active      = true,
            from        = .Iva,
            to          = .Niko,
            origin      = .East,
            destination = .West,
            subject     = "Meet me beneath the blue awning",
        }
    case .Together:
        eastbound := state.repeat_deliveries % 2 == 0
        delivery =
            eastbound ? Delivery{active = true, from = .Niko, to = .Iva, origin = .West, destination = .East, subject = "Bread, postcards, and one pressed flower"} : Delivery{active = true, from = .Iva, to = .Niko, origin = .East, destination = .West, subject = "Lamp glass and a note for supper"}
    }
    state.delivery = delivery
    return true
}

complete_delivery :: proc(state: ^State, recipient: Resident) -> bool {
    if state == nil || !state.delivery.active || state.delivery.to != recipient do return false
    state.delivery.active = false
    state.completed_deliveries += 1
    state.stamps_earned += 1
    if state.romance == .Invitation &&
       state.repair == .Repaired &&
       state.delivery.subject == "Meet me beneath the blue awning" {
        state.romance = .Together
    } else if state.romance == .Together {
        state.repeat_deliveries += 1
    }
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
    state.has_tool_roll = true
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

niko_intro :: proc(_: ^dialogue.Context) -> string {
    return(
        "The east-island lamp flashes twice before dawn. Iva is awake when my ovens are. Would you carry her something?" \
    )
}

iva_reply :: proc(_: ^dialogue.Context) -> string {
    return "He remembered the cardamom. Tell Niko the lamp flashes twice because once felt too lonely."
}

bojan_crash :: proc(_: ^dialogue.Context) -> string {
    return(
        "Landing was excellent. The ground arrived early. Help me inspect the wing before anyone invents a less flattering version." \
    )
}

bojan_repair :: proc(_: ^dialogue.Context) -> string {
    return(
        "Patch taut, ribs straight, controls free. Give the propeller one careful turn and we will call that engineering." \
    )
}

accept_niko_letter :: proc(ctx: ^dialogue.Context) {
    _ = begin_delivery(state_from_context(ctx))
}

accept_iva_reply :: proc(ctx: ^dialogue.Context) {
    _ = begin_delivery(state_from_context(ctx))
}

note_crash :: proc(ctx: ^dialogue.Context) {
    _ = report_crash(state_from_context(ctx))
}

inspect_crash :: proc(ctx: ^dialogue.Context) {
    _ = diagnose_crash(state_from_context(ctx))
}

confirm_repair :: proc(ctx: ^dialogue.Context) {
    _ = verify_repair(state_from_context(ctx))
}

can_begin_first_letter :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .Unintroduced && !state.delivery.active
}

can_begin_reply :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.romance == .First_Letter && !state.delivery.active
}

can_report_crash :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.repair == .Not_Seen
}

can_inspect_crash :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.repair == .Crash_Reported
}

can_verify_repair :: proc(ctx: ^dialogue.Context) -> bool {
    state := state_from_context(ctx)
    return state != nil && state.repair == .Patched
}

// Catalog owns fixed backing arrays so definitions can safely reference it for
// the lifetime of a game session without per-conversation allocation.
Catalog :: struct {
    niko_choices:  [2]dialogue.Choice,
    iva_choices:   [2]dialogue.Choice,
    bojan_choices: [4]dialogue.Choice,
    niko_nodes:    [1]dialogue.Node,
    iva_nodes:     [1]dialogue.Node,
    bojan_nodes:   [2]dialogue.Node,
    niko:          dialogue.Definition,
    iva:           dialogue.Definition,
    bojan:         dialogue.Definition,
}

init_catalog :: proc(catalog: ^Catalog) {
    if catalog == nil do return
    catalog^ = {}
    catalog.niko_choices = {
        dialogue.choice("I'll carry it across.", condition = can_begin_first_letter, effect = accept_niko_letter),
        dialogue.choice("Not just now."),
    }
    catalog.iva_choices = {
        dialogue.choice("I'll take your reply.", condition = can_begin_reply, effect = accept_iva_reply),
        dialogue.choice("Keep it safe for now."),
    }
    catalog.bojan_choices = {
        dialogue.choice("I saw the whole thing.", 1, can_report_crash, note_crash),
        dialogue.choice("Let's inspect the wing.", 1, can_inspect_crash, inspect_crash),
        dialogue.choice("Turn the propeller.", effect = confirm_repair, condition = can_verify_repair),
        dialogue.choice("I'll come back."),
    }
    catalog.niko_nodes[0] = dialogue.node("letter", niko_intro, catalog.niko_choices[:], niko_speaker)
    catalog.iva_nodes[0] = dialogue.node("reply", iva_reply, catalog.iva_choices[:], iva_speaker)
    catalog.bojan_nodes = {
        dialogue.node("crash", bojan_crash, catalog.bojan_choices[:], bojan_speaker),
        dialogue.node("repair", bojan_repair, catalog.bojan_choices[1:], bojan_speaker),
    }
    catalog.niko = {
        id    = "niko",
        nodes = catalog.niko_nodes[:],
    }
    catalog.iva = {
        id    = "iva",
        nodes = catalog.iva_nodes[:],
    }
    catalog.bojan = {
        id    = "bojan",
        nodes = catalog.bojan_nodes[:],
    }
}
