package player_mail

import "core:testing"

@(test)
mail_is_received_once_and_only_received_mail_can_be_read :: proc(t: ^testing.T) {
    state: State
    testing.expect(t, unread_count(&state) == 0)
    testing.expect(t, !mark_read(&state, .Welcome))
    testing.expect(t, receive(&state, .Welcome))
    testing.expect(t, !receive(&state, .Welcome))
    testing.expect(t, unread_count(&state) == 1)
    testing.expect(t, mark_read(&state, .Welcome))
    testing.expect(t, !mark_read(&state, .Welcome))
    testing.expect(t, unread_count(&state) == 0)
}

@(test)
every_letter_id_has_a_matching_definition :: proc(t: ^testing.T) {
    for id in Letter_ID {
        item := definition(id)
        testing.expect(t, item != nil)
        if item != nil {
            testing.expect(t, item.id == id)
            testing.expect(t, len(item.sender) > 0)
            testing.expect(t, len(item.subject) > 0)
            testing.expect(t, len(item.body) > 0)
        }
    }
}
