package tests

import dialogue "../packages/dialogue"
import story "../packages/story"
import "core:testing"

@(test)
two_island_love_story_becomes_repeatable_mail_route :: proc(t: ^testing.T) {
    state: story.State
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.from == .Niko && state.delivery.to == .Iva)
    testing.expect(t, story.complete_delivery(&state, .Iva))

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.origin == .East && state.delivery.destination == .West)
    testing.expect(t, story.complete_delivery(&state, .Niko))

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, story.complete_delivery(&state, .Iva))
    testing.expect(t, !story.begin_delivery(&state))

    testing.expect(t, story.report_crash(&state))
    testing.expect(t, story.diagnose_crash(&state))
    state.has_wing_patch = true
    testing.expect(t, story.apply_wing_patch(&state))
    testing.expect(t, story.verify_repair(&state))

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, story.complete_delivery(&state, .Niko))
    testing.expect(t, state.romance == .Together)

    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, story.complete_delivery(&state, .Iva))
    testing.expect(t, state.repeat_deliveries == 1 && state.stamps_earned == 5)
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, state.delivery.destination == .West)
}

@(test)
story_rejects_wrong_recipient_and_out_of_order_repair :: proc(t: ^testing.T) {
    state: story.State
    testing.expect(t, story.begin_delivery(&state))
    testing.expect(t, !story.complete_delivery(&state, .Niko))
    testing.expect(t, state.delivery.active)
    testing.expect(t, !story.diagnose_crash(&state))
    testing.expect(t, !story.apply_wing_patch(&state))
    testing.expect(t, !story.verify_repair(&state))
}

@(test)
character_dialogue_catalog_is_valid :: proc(t: ^testing.T) {
    catalog: story.Catalog
    story.init_catalog(&catalog)
    testing.expect(t, dialogue.validate(&catalog.niko))
    testing.expect(t, dialogue.validate(&catalog.iva))
    testing.expect(t, dialogue.validate(&catalog.bojan))
}
