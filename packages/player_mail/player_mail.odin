package player_mail

// Letter prose lives in immutable definitions. Saves retain only which
// definitions have reached the player and which have been opened.
Letter_ID :: enum u8 {
    Welcome,
    Mirna_Field_Notes,
    Postmasters_Thanks,
}

LETTER_COUNT :: 3

State :: struct {
    received: [LETTER_COUNT]bool,
    read:     [LETTER_COUNT]bool,
}

Definition :: struct {
    id:      Letter_ID,
    sender:  string,
    subject: string,
    body:    string,
}

definitions := [LETTER_COUNT]Definition {
    {
        id = .Welcome,
        sender = "Toma & Lena",
        subject = "Your poste restante box",
        body = "Courier—\n\nWe have opened a poste restante box in your name. Any letter addressed to you may be collected at either island post office. Once collected, it remains in your satchel for reading whenever the road, sea, or sky is quiet.\n\n—Toma & Lena",
    },
    {
        id = .Mirna_Field_Notes,
        sender = "Dr Mirna",
        subject = "Regarding the Friendometer",
        body = "Field researcher—\n\nPlease record any result the Friendometer calls impossible. Friendship is a scalar, naturally, but the instrument has developed an unfortunate interest in context. Do not encourage it.\n\n—Dr Mirna",
    },
    {
        id = .Postmasters_Thanks,
        sender = "Toma & Lena",
        subject = "The islands are noticing",
        body = "Courier—\n\nThe bags are lighter when you arrive and the counters are noisier after you leave. Both are signs of useful work. There will always be another crossing, but today the post is caught up. Thank you.\n\n—Toma & Lena",
    },
}

definition :: proc(id: Letter_ID) -> ^Definition {
    index := int(id)
    if index < 0 || index >= LETTER_COUNT do return nil
    return &definitions[index]
}

receive :: proc(state: ^State, id: Letter_ID) -> bool {
    if state == nil do return false
    index := int(id)
    if index < 0 || index >= LETTER_COUNT || state.received[index] do return false
    state.received[index] = true
    return true
}

mark_read :: proc(state: ^State, id: Letter_ID) -> bool {
    if state == nil do return false
    index := int(id)
    if index < 0 || index >= LETTER_COUNT || !state.received[index] do return false
    changed := !state.read[index]
    state.read[index] = true
    return changed
}

unread_count :: proc(state: ^State) -> int {
    if state == nil do return 0
    count := 0
    for received, index in state.received {
        if received && !state.read[index] do count += 1
    }
    return count
}
