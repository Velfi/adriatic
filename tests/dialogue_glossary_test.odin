package tests

import dialogue_glossary "../packages/dialogue_glossary"
import "core:testing"

@(test)
dialogue_glossary_finds_terms_without_ascii_case_sensitivity :: proc(t: ^testing.T) {
    english, found := dialogue_glossary.english_for("Bura")
    testing.expect(t, found)
    testing.expect(t, english == "strong north wind")
}

@(test)
dialogue_glossary_finds_elided_terms :: proc(t: ^testing.T) {
    forms := [?]string{"l'isola", "dell'isola", "L’ISOLA"}
    for form in forms {
        english, found := dialogue_glossary.english_for(form)
        testing.expect(t, found)
        testing.expect(t, english == "island")
    }
}

@(test)
dialogue_glossary_keeps_opaque_regional_terms :: proc(t: ^testing.T) {
    bura, found_bura := dialogue_glossary.english_for("bura")
    persiana, found_persiana := dialogue_glossary.english_for("persiana")
    testing.expect(t, found_bura && bura == "strong north wind")
    testing.expect(t, found_persiana && persiana == "window shutter")
}

@(test)
dialogue_glossary_does_not_mark_familiar_foreign_words :: proc(t: ^testing.T) {
    familiar_terms := [?]string{"ciao", "grazie", "buongiorno", "sì", "regatta"}
    for familiar in familiar_terms {
        _, found := dialogue_glossary.english_for(familiar)
        testing.expect(t, !found)
    }
}

@(test)
dialogue_glossary_does_not_mark_names_or_quest_items :: proc(t: ^testing.T) {
    ordinary_terms := [?]string{"Marta", "Gerta", "Iva", "Niko", "magneto", "invitation", "letter", "propeller"}
    for term in ordinary_terms {
        _, found := dialogue_glossary.english_for(term)
        testing.expect(t, !found)
    }
}
