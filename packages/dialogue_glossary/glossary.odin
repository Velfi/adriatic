package dialogue_glossary

// Product-local vocabulary used by the dialogue presentation. The branching
// dialogue runtime remains language-agnostic; Adriatic's deliberately mixed
// island dialect belongs here.
Entry :: struct {
    term:    string,
    english: string,
}

entries := [?]Entry {
    {"baia", "bay"},
    {"bura", "strong north wind"},
    {"cena", "dinner"},
    {"corriere", "courier"},
    {"dobar", "good"},
    {"dobro", "good"},
    {"faro", "lighthouse"},
    {"isola", "island"},
    {"jutro", "morning"},
    {"lampe", "lamp"},
    {"mare", "sea"},
    {"nema", "no / there is none"},
    {"pane", "bread"},
    {"phare", "lighthouse"},
    {"persiana", "window shutter"},
    {"posta", "mail"},
    {"risposta", "reply"},
    {"sigillata", "sealed"},
    {"tenda", "tent"},
    {"traversée", "crossing"},
    {"vento", "wind"},
    {"verre", "glass"},
}

ascii_equal_fold :: proc(a, b: string) -> bool {
    if len(a) != len(b) do return false
    for index in 0 ..< len(a) {
        byte := a[index]
        other := b[index]
        folded := byte
        if folded >= 'A' && folded <= 'Z' do folded += 'a' - 'A'
        if other >= 'A' && other <= 'Z' do other += 'a' - 'A'
        if folded != other do return false
    }
    return true
}

english_for :: proc(term: string) -> (string, bool) {
    for entry in entries {
        if ascii_equal_fold(term, entry.term) do return entry.english, true
    }
    // Dialogue commonly elides an article or preposition before a noun
    // (l'isola, dell'isola). Try the bare suffix after the final ASCII or
    // curly apostrophe so authors do not need duplicate glossary entries.
    suffix_start := 0
    for index := 0; index < len(term); index += 1 {
        if term[index] == '\'' {
            suffix_start = index + 1
        } else if index + 2 < len(term) && term[index] == 0xe2 && term[index + 1] == 0x80 && term[index + 2] == 0x99 {
            suffix_start = index + 3
            index += 2
        }
    }
    if suffix_start > 0 && suffix_start < len(term) {
        suffix := term[suffix_start:]
        for entry in entries {
            if ascii_equal_fold(suffix, entry.term) do return entry.english, true
        }
    }
    return "", false
}
