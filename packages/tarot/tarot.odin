package tarot

// Renderer-independent tarot rules. Cards are numbered in Rider-Waite order:
// the 22 major arcana, then Ace through King for Wands, Cups, Swords, Pentacles.

CARD_COUNT :: 78
MAX_PLACEMENTS :: 10

Spread :: enum {
    Single,
    Three_Card,
    Celtic_Cross,
}

Orientation :: enum {
    Upright,
    Reversed,
}

Card :: distinct u8

Placement :: struct {
    card:        Card,
    orientation: Orientation,
    position:    string,
}

Layout :: struct {
    spread:     Spread,
    placements: [MAX_PLACEMENTS]Placement,
    count:      int,
    seed:       u32,
}

spread_name :: proc(spread: Spread) -> string {
    switch spread {
    case .Single:
        return "One card"
    case .Three_Card:
        return "Past · Present · Possible"
    case .Celtic_Cross:
        return "Celtic Cross"
    }
    return ""
}

spread_count :: proc(spread: Spread) -> int {
    switch spread {
    case .Single:
        return 1
    case .Three_Card:
        return 3
    case .Celtic_Cross:
        return 10
    }
    return 0
}

position_name :: proc(spread: Spread, index: int) -> string {
    if index < 0 || index >= spread_count(spread) do return ""
    switch spread {
    case .Single:
        return "The matter"
    case .Three_Card:
        names := [?]string{"Past", "Present", "Possible"}
        return names[index]
    case .Celtic_Cross:
        names := [?]string {
            "The heart",
            "What crosses it",
            "The root",
            "What is passing",
            "What may come",
            "The near shore",
            "Your footing",
            "The weather around you",
            "Hopes and cautions",
            "The farther shore",
        }
        return names[index]
    }
    return ""
}

card_name :: proc(card: Card) -> string {
    id := int(card)
    if id < 0 || id >= CARD_COUNT do return ""
    majors := [?]string {
        "The Fool",
        "The Magician",
        "The High Priestess",
        "The Empress",
        "The Emperor",
        "The Hierophant",
        "The Lovers",
        "The Chariot",
        "Strength",
        "The Hermit",
        "Wheel of Fortune",
        "Justice",
        "The Hanged Mouse",
        "Death",
        "Temperance",
        "The Devil",
        "The Tower",
        "The Star",
        "The Moon",
        "The Sun",
        "Judgement",
        "The World",
    }
    if id < len(majors) do return majors[id]
    minor := id - len(majors)
    rank, suit := minor % 14, minor / 14
    // All returned combinations are static strings so callers never own memory.
    minor_names := [?][14]string {
        {
            "Ace of Wands",
            "Two of Wands",
            "Three of Wands",
            "Four of Wands",
            "Five of Wands",
            "Six of Wands",
            "Seven of Wands",
            "Eight of Wands",
            "Nine of Wands",
            "Ten of Wands",
            "Page of Wands",
            "Knight of Wands",
            "Queen of Wands",
            "King of Wands",
        },
        {
            "Ace of Cups",
            "Two of Cups",
            "Three of Cups",
            "Four of Cups",
            "Five of Cups",
            "Six of Cups",
            "Seven of Cups",
            "Eight of Cups",
            "Nine of Cups",
            "Ten of Cups",
            "Page of Cups",
            "Knight of Cups",
            "Queen of Cups",
            "King of Cups",
        },
        {
            "Ace of Swords",
            "Two of Swords",
            "Three of Swords",
            "Four of Swords",
            "Five of Swords",
            "Six of Swords",
            "Seven of Swords",
            "Eight of Swords",
            "Nine of Swords",
            "Ten of Swords",
            "Page of Swords",
            "Knight of Swords",
            "Queen of Swords",
            "King of Swords",
        },
        {
            "Ace of Pentacles",
            "Two of Pentacles",
            "Three of Pentacles",
            "Four of Pentacles",
            "Five of Pentacles",
            "Six of Pentacles",
            "Seven of Pentacles",
            "Eight of Pentacles",
            "Nine of Pentacles",
            "Ten of Pentacles",
            "Page of Pentacles",
            "Knight of Pentacles",
            "Queen of Pentacles",
            "King of Pentacles",
        },
    }
    return minor_names[suit][rank]
}

next_random :: proc(state: ^u32) -> u32 {
    // A non-zero xorshift32 state gives deterministic layouts without a runtime
    // random dependency, which also makes save games and tests reproducible.
    if state^ == 0 do state^ = 0x5441524f
    x := state^
    x ~= x << 13
    x ~= x >> 17
    x ~= x << 5
    state^ = x
    return x
}

deal :: proc(spread: Spread, seed: u32, allow_reversals := true) -> Layout {
    result := Layout {
        spread = spread,
        seed   = seed,
    }
    deck: [CARD_COUNT]Card
    for &card, index in deck do card = Card(index)
    random_state := seed
    for i := CARD_COUNT - 1; i > 0; i -= 1 {
        j := int(next_random(&random_state) % u32(i + 1))
        deck[i], deck[j] = deck[j], deck[i]
    }
    result.count = spread_count(spread)
    for i in 0 ..< result.count {
        result.placements[i] = {
            card        = deck[i],
            orientation = allow_reversals && (next_random(&random_state) & 1) != 0 ? .Reversed : .Upright,
            position    = position_name(spread, i),
        }
    }
    return result
}

valid :: proc(layout: ^Layout) -> bool {
    if layout == nil || layout.count != spread_count(layout.spread) do return false
    seen: [CARD_COUNT]bool
    for placement, index in layout.placements[:layout.count] {
        id := int(placement.card)
        if id < 0 || id >= CARD_COUNT || seen[id] do return false
        if placement.position != position_name(layout.spread, index) do return false
        seen[id] = true
    }
    return true
}
