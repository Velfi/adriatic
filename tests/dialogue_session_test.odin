package tests

import dialogue_session "../packages/dialogue_session"
import "core:testing"

@(test)
dialogue_session_rejects_cross_domain_effects :: proc(t: ^testing.T) {
    session: dialogue_session.State

    dialogue_session.begin(&session, .Story)
    testing.expect(t, !dialogue_session.set_airfield(&session, .Select_Aircraft))
    testing.expect(t, !dialogue_session.set_marina(&session, .Borrow_Dinghy))
    testing.expect(t, session.airfield == .None)
    testing.expect(t, session.marina == .None)

    dialogue_session.begin(&session, .Airfield_Services)
    testing.expect(t, dialogue_session.set_airfield(&session, .Paint_Aircraft))
    testing.expect(t, !dialogue_session.set_marina(&session, .Borrow_Dinghy))
    testing.expect(t, session.airfield == .Paint_Aircraft)
    testing.expect(t, session.marina == .None)

    dialogue_session.begin(&session, .Marina_Dockmaster)
    testing.expect(t, dialogue_session.set_marina(&session, .Borrow_Dinghy))
    testing.expect(t, !dialogue_session.set_airfield(&session, .Select_Aircraft))
    testing.expect(t, session.airfield == .None)
    testing.expect(t, session.marina == .Borrow_Dinghy)
}

@(test)
opening_a_dialogue_session_clears_the_previous_result :: proc(t: ^testing.T) {
    session: dialogue_session.State
    dialogue_session.begin(&session, .Airfield_Services)
    testing.expect(t, dialogue_session.set_airfield(&session, .Select_Aircraft))

    dialogue_session.begin(&session, .Story)
    testing.expect(t, session.kind == .Story)
    testing.expect(t, session.airfield == .None)
    testing.expect(t, session.marina == .None)
}
