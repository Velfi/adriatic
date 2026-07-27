package tests

import tarot "../packages/tarot"
import "core:testing"

@(test)
tarot_deals_complete_unique_deterministic_layouts :: proc(t: ^testing.T) {
    for spread in tarot.Spread {
        first := tarot.deal(spread, 0x12345678)
        second := tarot.deal(spread, 0x12345678)
        testing.expect(t, tarot.valid(&first))
        testing.expect(t, first == second)
        testing.expect(t, first.count == tarot.spread_count(spread))
        for placement, index in first.placements[:first.count] {
            testing.expect(t, placement.position == tarot.position_name(spread, index))
            testing.expect(t, tarot.card_name(placement.card) != "")
        }
    }
}

@(test)
tarot_reversals_can_be_disabled :: proc(t: ^testing.T) {
    layout := tarot.deal(.Celtic_Cross, 41, false)
    for placement in layout.placements[:layout.count] {
        testing.expect(t, placement.orientation == .Upright)
    }
}
