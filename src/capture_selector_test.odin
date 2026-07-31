package main

import "core:testing"

@(test)
capture_selector_parses_typed_identity_filters_and_pick :: proc(t: ^testing.T) {
    filters: [CAPTURE_SELECTOR_FILTER_CAPACITY]string
    filters[0] = "available=true"
    selector, message, ok := capture_selector_parse("vehicle:postale", filters, 1, "2")
    testing.expect(t, ok, message)
    testing.expect_value(t, selector.kind, Capture_Subject_Kind.Vehicle)
    testing.expect_value(t, selector.identity, "postale")
    testing.expect_value(t, selector.filter_count, 1)
    testing.expect_value(t, selector.pick, 1)
    testing.expect(t, selector.pick_set)
}

@(test)
capture_selector_rejects_unknown_kinds_and_malformed_filters :: proc(t: ^testing.T) {
    filters: [CAPTURE_SELECTOR_FILTER_CAPACITY]string
    _, _, unknown_ok := capture_selector_parse("widget:bell", filters, 0, "")
    testing.expect(t, !unknown_ok)
    filters[0] = "available"
    _, _, filter_ok := capture_selector_parse("vehicle", filters, 1, "")
    testing.expect(t, !filter_ok)
}

@(test)
capture_subject_filters_use_runtime_attributes :: proc(t: ^testing.T) {
    subject := Capture_Subject {
        kind      = .Vehicle,
        id        = 104,
        name      = "Rondine",
        subtype   = "Rondine",
        available = false,
    }
    testing.expect(t, capture_subject_matches_identity(subject, "rondine"))
    testing.expect(t, capture_subject_matches_filter(subject, "id=104"))
    testing.expect(t, capture_subject_matches_filter(subject, "available=false"))
    testing.expect(t, !capture_subject_matches_filter(subject, "available=true"))
}
