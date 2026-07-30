package main

import fixture_v0005 "../packages/fixture_history/v0005"
import terrain "../packages/terrain"
import "core:mem"

FIXTURE_MIGRATION_V0005_TO_V0006_FROM_VERSION :: 5
FIXTURE_MIGRATION_V0005_TO_V0006_TO_VERSION :: 6
FIXTURE_MIGRATION_V0005_TO_V0006_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/buildings.Archetype.Lighthouse",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/buildings.Landmark_Kind.Lighthouse",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:packages/roads.Pavement.Steps", kind = .Automatic},
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/story.Delivery_Kind.Clinic_Linens",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/story.Delivery_Kind.Clinic_Medicine",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/story.Delivery_Kind.Clinic_Water",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/terrain.Formation_Kind.Ruins",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:src.Settlement_Acceptance_Failure.Road_Topology",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:src.Settlement_Landmark_Kind.Lighthouse",
        kind = .Automatic,
    },
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:src.Settlement_Site_Kind.Ruin", kind = .Automatic},
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Building_Access",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Fabric_Form",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Height_Band",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Height_Outlier",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Insufficient_Buildings",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Landmark_Count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Missing_Blocks",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Missing_Buildings",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Missing_Village_Program",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Park_Count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Route_Grade",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Submerged_Route",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Submerged_Site",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Site_Kind.Rejected",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/farmland.Plan.garden_span",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:packages/farmland.Plan.garden_x", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:packages/farmland.Plan.garden_z", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:packages/roads.Edge.use_intensity", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:packages/story.Delivery.care", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:packages/story.State.bonus_stamps", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.careful_deliveries",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.expressive_deliveries",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.has_clinic_satchel",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:packages/story.State.has_dry_wrap", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.has_recovery_kit",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.has_weather_briefing",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.last_clinic_visit_was_tumble",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.linens_delivered",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.magneto_wrapped",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.medicine_delivered",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.water_delivered",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.weather_reading_done",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Fixture.harbor_authored_intervention",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.harbor_authored_plan", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Player_Animation_Tweak.body_softness_damping",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Player_Animation_Tweak.body_softness_inertial_lag",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Player_Animation_Tweak.body_softness_influence_radius",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Player_Animation_Tweak.body_softness_max_displacement",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Player_Animation_Tweak.body_softness_stiffness",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Player_Animation_Tweak.body_softness_strength",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Player_Animation_Tweak.body_softness_volume_return",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.access_repair_share",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.degree_four_plus_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.drivable_dead_end_share",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.paved_length_per_building",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.public_component_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.public_cycle_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.public_max_degree",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.public_paving_per_building",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.public_route_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_repair_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Settlement_Plan.garden_count", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Settlement_Plan.gardens", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.growth_event_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Settlement_Plan.growth_events", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Settlement_Plan.patio_count", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Settlement_Plan.patios", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Site.fountain_enabled",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Site.fountain_jet_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Site.fountain_jet_height",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Site.fountain_radius",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Site.fountain_style",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/terrain.Clipmap_Level.heights",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/terrain.Clipmap_Level.material",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/terrain.Project.city_density",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/terrain.Project.climbing_leaf_density",
        kind = .Scripted,
    },
}

fixture_migrate_v0005_to_v0006 :: proc(
    #by_ptr historical: fixture_v0005.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = historical
    return fixture_migration_v0005_to_v0006_tentative(tentative, allocator)
}

fixture_migration_v0005_to_v0006_mix :: proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * u32(0x7feb352d)
    result = (result ~ (result >> 15)) * u32(0x846ca68b)
    return result ~ (result >> 16)
}

fixture_migration_v0005_to_v0006_site_kind :: proc(kind: Settlement_Site_Kind) -> (Settlement_Site_Kind, bool) {
    value := int(kind)
    if value < 0 || value > 3 do return {}, false
    if value == 3 do value = 4
    return Settlement_Site_Kind(value), true
}

fixture_migration_v0005_to_v0006_acceptance_failure :: proc(
    failure: Settlement_Acceptance_Failure,
) -> (
    Settlement_Acceptance_Failure,
    bool,
) {
    value := int(failure)
    if value < 0 || value > 17 do return {}, false
    if value >= 5 do value += 1
    return Settlement_Acceptance_Failure(value), true
}

fixture_migration_v0005_to_v0006_tentative :: proc(
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    if tentative == nil || allocator.procedure == nil {
        return {kind = .Invalid_Argument}
    }
    if tentative.project.structure_count < 0 ||
       tentative.project.structure_count > len(tentative.project.structures) ||
       tentative.project.road_graph.edge_count < 0 ||
       tentative.project.road_graph.edge_count > len(tentative.project.road_graph.edges) ||
       tentative.farm_count < 0 ||
       tentative.farm_count > len(tentative.farms) ||
       tentative.settlement_plan.site_count < 0 ||
       tentative.settlement_plan.site_count > len(tentative.settlement_plan.sites) ||
       tentative.settlement_plan.rejected_site_count < 0 ||
       tentative.settlement_plan.rejected_site_count > len(tentative.settlement_plan.rejected_sites) {
        return {kind = .Invalid_Source, change_id = "field-type:adriatic:packages/terrain.Clipmap_Level.heights"}
    }

    legacy_levels := new([terrain.CLIPMAP_LEVELS]terrain.Clipmap_Level_V6, allocator)
    if legacy_levels == nil {
        return {kind = .Out_Of_Memory, change_id = "field-type:adriatic:packages/terrain.Clipmap_Level.heights"}
    }
    terrain_levels_valid := true
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        source := &tentative.project.levels[level_index]
        if source.cell_size <= 0 || source.cell_size != source.cell_size {
            terrain_levels_valid = false
            break
        }
        legacy := &legacy_levels[level_index]
        legacy.cell_size = source.cell_size
        legacy.origin_x = source.origin_x
        legacy.origin_z = source.origin_z
        copy(legacy.heights[:], source.heights[:terrain.LEGACY_TERRAIN_SAMPLES])
        copy(legacy.material[:], source.material[:terrain.LEGACY_TERRAIN_SAMPLES])
    }
    if terrain_levels_valid {
        terrain.terrain_levels_migrate_v6(&tentative.project.levels, legacy_levels)
    } else {
        // Empty historical fixtures have no initialized terrain. Preserve
        // that empty state without sampling through a zero cell size.
        tentative.project.levels = {}
    }

    // Density fields still use the 256×256 ring grid. Preserve those samples
    // in place and intentionally leave the newly allocated tail zeroed.
    for index in terrain.LEGACY_TERRAIN_SAMPLES ..< len(tentative.project.city_density) {
        tentative.project.city_density[index] = 0
        tentative.project.climbing_leaf_density[index] = 0
    }

    // Existing roads predate authored traffic intensity and represent normal,
    // maintained circulation rather than abandoned routes.
    for &edge in tentative.project.road_graph.edges[:tentative.project.road_graph.edge_count] {
        edge.use_intensity = 1
    }

    // Reconstruct the deterministic kitchen-garden placement introduced in v6
    // from each farm's existing seed and dimensions.
    for &farm in tentative.farms[:tentative.farm_count] {
        plan := &farm.plan
        if plan.width <= 0 || plan.height <= 0 {
            plan.garden_x, plan.garden_z, plan.garden_span = 0, 0, 0
            continue
        }
        plan.garden_span = clamp(min(plan.width, plan.height) / 5, 1, 3)
        plan.garden_x = 1
        if (fixture_migration_v0005_to_v0006_mix(plan.seed ~ u32(0x47415244)) & 1) != 0 {
            plan.garden_x = plan.width - plan.garden_span - 1
        }
        plan.garden_z = 1
        if (fixture_migration_v0005_to_v0006_mix(plan.seed ~ u32(0x4b495443)) & 1) != 0 {
            plan.garden_z = plan.height - plan.garden_span - 1
        }
    }

    // These are new progression counters and flags. Zero/false means the
    // historical save has not completed content that did not yet exist.
    tentative.story_state.delivery.care = .Unchosen
    tentative.story_state.bonus_stamps = 0
    tentative.story_state.careful_deliveries = 0
    tentative.story_state.expressive_deliveries = 0
    tentative.story_state.magneto_wrapped = false
    tentative.story_state.weather_reading_done = false
    tentative.story_state.medicine_delivered = false
    tentative.story_state.linens_delivered = false
    tentative.story_state.water_delivered = false
    tentative.story_state.has_weather_briefing = false
    tentative.story_state.has_clinic_satchel = false
    tentative.story_state.has_dry_wrap = false
    tentative.story_state.has_recovery_kit = false
    tentative.story_state.last_clinic_visit_was_tumble = false

    // Old fixtures have no separately authored harbor. Its zero value is an
    // invalid/empty plan and intervention, so the existing marina remains the
    // sole durable waterfront state until the user authors a harbor.
    tentative.harbor_authored_plan = {}
    tentative.harbor_authored_intervention = {}

    default_tweak := tweak_default_state().player_animation
    tentative.tweak.player_animation.body_softness_strength = default_tweak.body_softness_strength
    tentative.tweak.player_animation.body_softness_influence_radius = default_tweak.body_softness_influence_radius
    tentative.tweak.player_animation.body_softness_volume_return = default_tweak.body_softness_volume_return
    tentative.tweak.player_animation.body_softness_stiffness = default_tweak.body_softness_stiffness
    tentative.tweak.player_animation.body_softness_damping = default_tweak.body_softness_damping
    tentative.tweak.player_animation.body_softness_inertial_lag = default_tweak.body_softness_inertial_lag
    tentative.tweak.player_animation.body_softness_max_displacement = default_tweak.body_softness_max_displacement

    for &site in tentative.settlement_plan.sites[:tentative.settlement_plan.site_count] {
        kind, ok := fixture_migration_v0005_to_v0006_site_kind(site.kind)
        if !ok {
            return {kind = .Invalid_Source, change_id = "enum-value:adriatic:src.Settlement_Site_Kind.Rejected"}
        }
        site.kind = kind
        site.fountain_enabled = false
        site.fountain_jet_count = 0
        site.fountain_jet_height = 0
        site.fountain_radius = 0
        site.fountain_style = {}
    }
    for &site in tentative.settlement_plan.rejected_sites[:tentative.settlement_plan.rejected_site_count] {
        kind, ok := fixture_migration_v0005_to_v0006_site_kind(site.kind)
        if !ok {
            return {kind = .Invalid_Source, change_id = "enum-value:adriatic:src.Settlement_Site_Kind.Rejected"}
        }
        site.kind = kind
        site.fountain_enabled = false
        site.fountain_jet_count = 0
        site.fountain_jet_height = 0
        site.fountain_radius = 0
        site.fountain_style = {}
    }
    failure, failure_ok := fixture_migration_v0005_to_v0006_acceptance_failure(
        tentative.settlement_plan.acceptance_failure,
    )
    if !failure_ok {
        return {
            kind = .Invalid_Source,
            change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Building_Access",
        }
    }
    tentative.settlement_plan.acceptance_failure = failure

    // New settlement growth, patio, garden, repair, and topology metrics are
    // generated outputs. Historical plans preserve their existing authored
    // content while these new collections and counters begin empty.
    tentative.settlement_plan.access_repair_count = 0
    tentative.settlement_plan.growth_events = {}
    tentative.settlement_plan.growth_event_count = 0
    tentative.settlement_plan.gardens = {}
    tentative.settlement_plan.garden_count = 0
    tentative.settlement_plan.patios = {}
    tentative.settlement_plan.patio_count = 0
    tentative.settlement_plan.metrics.drivable_dead_end_share = 0
    tentative.settlement_plan.metrics.degree_four_plus_count = 0
    tentative.settlement_plan.metrics.paved_length_per_building = 0
    tentative.settlement_plan.metrics.public_paving_per_building = 0
    tentative.settlement_plan.metrics.access_repair_share = 0
    tentative.settlement_plan.metrics.public_route_count = 0
    tentative.settlement_plan.metrics.public_component_count = 0
    tentative.settlement_plan.metrics.public_cycle_count = 0
    tentative.settlement_plan.metrics.public_max_degree = 0
    return {}
}
