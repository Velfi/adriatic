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
    return "", false
}
