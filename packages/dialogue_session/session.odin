package dialogue_session

// Product-facing dialogue effects are scoped by session kind. The reusable
// dialogue package owns graph traversal; this package prevents one host
// dialogue from publishing a result that belongs to another.

Kind :: enum {
    None,
    Airfield_Services,
    Marina_Dockmaster,
    Story,
}

Airfield_Result :: enum {
    None,
    Paint_Aircraft,
    Select_Aircraft,
    Close,
}

Marina_Result :: enum {
    None,
    Borrow_Dinghy,
    Close,
}

State :: struct {
    kind:     Kind,
    airfield: Airfield_Result,
    marina:   Marina_Result,
}

begin :: proc(state: ^State, kind: Kind) {
    if state == nil do return
    state^ = {
        kind = kind,
    }
}

clear :: proc(state: ^State) {
    if state == nil do return
    state^ = {}
}

set_airfield :: proc(state: ^State, result: Airfield_Result) -> bool {
    if state == nil || state.kind != .Airfield_Services do return false
    state.airfield = result
    return true
}

set_marina :: proc(state: ^State, result: Marina_Result) -> bool {
    if state == nil || state.kind != .Marina_Dockmaster do return false
    state.marina = result
    return true
}
