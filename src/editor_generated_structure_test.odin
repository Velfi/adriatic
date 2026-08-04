package main

import buildings "../packages/buildings"
import "core:testing"

@(test)
editor_reclassifies_house_as_storefront_with_commercial_purpose :: proc(t: ^testing.T) {
    identity := buildings.Identity {
        archetype = .Townhouse,
        purpose = .Dwelling,
        region = .Adriatic,
        landmark_kind = .None,
    }

    storefront := editor_architecture_identity_reclassified(identity, 1)

    testing.expect_value(t, storefront.archetype, buildings.Archetype.Shop_House)
    testing.expect_value(t, storefront.purpose, buildings.Purpose.Inn_Shop)
    testing.expect_value(t, storefront.region, buildings.Region.Adriatic)
    testing.expect_value(t, storefront.landmark_kind, buildings.Landmark_Kind.None)
}

@(test)
editor_reclassification_wraps_and_clears_landmark_classification :: proc(t: ^testing.T) {
    identity := buildings.Identity {
        archetype = .Lighthouse,
        purpose = .Dwelling,
        region = .Aegean,
        landmark_kind = .Lighthouse,
    }

    reclassified := editor_architecture_identity_reclassified(identity, -1)

    testing.expect_value(t, reclassified.archetype, buildings.Archetype.Post_Office)
    testing.expect_value(t, reclassified.purpose, buildings.Purpose.Dwelling)
    testing.expect_value(t, reclassified.region, buildings.Region.Aegean)
    testing.expect_value(t, reclassified.landmark_kind, buildings.Landmark_Kind.Post_Office)
}
