package main

Capture_Kind :: enum {
    None,
    Editor,
    Formation,
    Map,
    Flight,
    Car,
    Vehicle_Showcase,
    Paint_Mode,
    Road,
    Road_Dust,
    Road_Grip,
    Terrain_Grip,
    Building,
    Story_Meeting,
    Foliage,
    Foliage_Forest,
    Foliage_Forest_Low,
    Foliage_Understory,
    Foliage_Golden,
    Foliage_Wind_A,
    Foliage_Wind_B,
    Foliage_Low_Wind_A,
    Foliage_Low_Wind_B,
    Foliage_Stress,
    Grass_Wind,
    Witch_Lab,
    Screen_Pops_Lab,
    Wildflower_Lab,
    Rainbow_Lab,
    Shadow_Lab,
    Rock_Lab,
    Boat_Lab,
    Boid_Lab,
    Car_Generator_Lab,
    Patio_Lab,
    Garden_Lab,
    Plant_Generator_Lab,
    Leaf_Generator_Lab,
    Flower_Generator_Lab,
    Window_Generator_Lab,
    Bridge_Generator_Lab,
    Fountain_Generator_Lab,
    Umbrella_Generator_Lab,
    Cemetery_Generator_Lab,
    Estuary_Delta_Lab,
    Rocky_Beach_Lab,
    Windmill_Generator_Lab,
    Hero_Building_Lab,
    Lighthouse_Lab,
    Mouse_Gait_Lab,
    Mouse_Theater,
    Rondine_Movement_Lab,
    Aircraft_Transform_Lab,
    Markov_Wreck,
    Markov_Farmland,
    Foliage_Transition_Lab,
    Markov_Marina,
    Ruins_Lab,
    Markov_Town,
    Markov_City,
    Markov_Village,
    Aegean_City,
    Aegean_Town,
    Aegean_Village,
    Narrow,
    Compact,
    Sky_Noon,
    Sky_Sunrise,
    Sky_Sunset,
    Sky_Storm,
    Sky_Night,
}

Capture_Request :: struct {
    kind:                    Capture_Kind,
    output_path:             string,
    target:                  string,
    window_width:            int,
    window_height:           int,
    settle_frames:           int,
    visual_style:            Visual_Style,
    dither_mode:             Dither_Mode,
    photo_filter_mode:       Photo_Filter_Mode,
    photo_filter_enabled:    bool,
    camera_eye:              [3]f32,
    camera_look_at:          [3]f32,
    camera_eye_set:          bool,
    camera_look_at_set:      bool,
    camera_orbit_degrees:    [2]f32,
    camera_orbit_set:        bool,
    camera_distance:         f32,
    camera_distance_set:     bool,
    camera_offset:           [3]f32,
    camera_offset_set:       bool,
    turntable_frames:        int,
    plant_sheet_views:       bool,
    seed_frames:             int,
    seed_start:              u64,
    sequence_frames:         int,
    sequence_fps:            int,
    selector:                string,
    selector_filters:        [CAPTURE_SELECTOR_FILTER_CAPACITY]string,
    selector_filter_count:   int,
    selector_pick:           string,
    presentation:            string,
    selector_failed:         bool,
    emote_name:              string,
    emote_time:              f32,
    emote_time_set:          bool,
    emote_handedness:        Mouse_Emote_Handedness,
    emote_seed:              u32,
    emote_target:            [3]f32,
    emote_target_set:        bool,
    emote_headgear:          Mouse_Accessory,
    emote_headgear_set:      bool,
    emote_scarf:             bool,
    emote_scarf_set:         bool,
    emote_mailbag:           bool,
    emote_mailbag_set:       bool,
    emote_ground_normal:     [3]f32,
    emote_ground_normal_set: bool,
}

cinematic_export_active: bool
cinematic_export_time: f32

CAPTURE_SKY_KINDS :: bit_set[Capture_Kind]{.Sky_Noon, .Sky_Sunrise, .Sky_Sunset, .Sky_Storm, .Sky_Night}
CAPTURE_BOAT_LAB_TARGETS := [?]string{"dinghy", "tanker", "cruise"}
CAPTURE_FOLIAGE_TARGETS := [?]string{"overview", "stress", "field"}
CAPTURE_FOLIAGE_FOREST_TARGETS := [?]string {
    "canopy",
    "low",
    "understory",
    "golden",
    "wind-a",
    "wind-b",
    "low-wind-a",
    "low-wind-b",
}
CAPTURE_FOLIAGE_FOREST_KINDS :: bit_set[Capture_Kind] {
    .Foliage_Forest,
    .Foliage_Forest_Low,
    .Foliage_Understory,
    .Foliage_Golden,
    .Foliage_Wind_A,
    .Foliage_Wind_B,
    .Foliage_Low_Wind_A,
    .Foliage_Low_Wind_B,
}
CAPTURE_FOLIAGE_MOTION_KINDS :: bit_set[Capture_Kind] {
    .Foliage_Wind_A,
    .Foliage_Wind_B,
    .Foliage_Low_Wind_A,
    .Foliage_Low_Wind_B,
}
CAPTURE_FOLIAGE_LOW_KINDS :: bit_set[Capture_Kind] {
    .Foliage_Forest_Low,
    .Foliage_Understory,
    .Foliage_Low_Wind_A,
    .Foliage_Low_Wind_B,
}

CAPTURE_BUILDING_TARGETS := [?]string {
    "<ordinal>",
    "ground-<ordinal>",
    "stoop-straight",
    "stoop-left",
    "stoop-right",
    "cypress",
    "mouse-town",
    "west-town-review",
    "east-town-review",
    "municipal-route-night",
    "municipal-route-night-storm",
    "plaza",
    "plaza-night",
    "plaza-night-new-moon",
    "plaza-night-full-moon",
    "plaza-night-storm",
    "mouse-wheel-plaza",
    "storefront",
    "storefront-front",
    "storefront-generated",
    "storefront-generated-night",
    "storefront-night",
    "storefront-night-storm",
    "bougainvillea-<seed>",
    "storefront-plant-<seed>",
    "storefront-display-<seed>",
    "storefront-night-display-<seed>",
    "storefront-angle-<seed>",
    "storefront-plan-<seed>",
}
CAPTURE_FLIGHT_TARGETS := [?]string {
    "postale",
    "rondine",
    "rondine-launch",
    "rondine-landing",
    "rondine-drift",
    "rondine-countersteer",
    "rondine-countersteer-left",
    "rondine-breakaway",
    "rondine-hookup",
}
CAPTURE_CAR_TARGETS := [?]string {
    "asphalt",
    "gravel",
    "cobble",
    "cobble-clean",
    "cobble-grassy-clean",
    "cobble-junction-clean",
    "cobble-night-clean",
    "cobble-storm-clean",
    "dirt",
}
CAPTURE_SKY_TARGETS := [?]string{"sun", "sun-air", "sun-away", "moon", "stars"}
CAPTURE_RAINBOW_TARGETS := [?]string{"shower", "dry", "double"}
CAPTURE_STORY_MEETING_TARGETS := [?]string {
    "wipe-left",
    "wipe-right",
    "wipe-up",
    "wipe-down",
    "wipe-iris",
    "wipe-clockwise",
    "wipe-checker",
}
CAPTURE_MOUSE_GAIT_TARGETS := [?]string{"stop-spray", "scurry"}
CAPTURE_PATIO_TARGETS := [?]string{"coastal", "courtyard", "evening"}
CAPTURE_GARDEN_TARGETS := [?]string{"courtyard", "kitchen", "wild", "stone", "alternate"}
CAPTURE_PLANT_GENERATOR_TARGETS := [?]string {
    "<species>-sheet",
    "gallery",
    "climbing-garden",
    "succulent-garden",
    "olive",
    "olive-71",
    "olive-79",
    "olive-young",
    "olive-growing",
    "olive-medium",
    "olive-far",
    "olive-trunk",
    "cypress",
    "cypress-seed-<seed>",
    "cypress-cones",
    "cypress-base",
    "cypress-young",
    "cypress-growing",
    "cypress-medium",
    "cypress-far",
    "grapevine",
    "fig",
    "lemon",
    "lemon-seed-<seed>",
    "lemon-fruit",
    "lemon-young",
    "lemon-medium",
    "lemon-far",
    "pomegranate",
    "almond",
    "oleander",
    "bougainvillea",
    "climber-interior-corner",
    "climber-interior-corner-seed-<seed>",
    "rosemary",
    "stone-pine",
    "bay-laurel",
    "carob",
    "strawberry-tree",
    "myrtle",
    "mastic",
    "lavender",
    "thyme",
    "sage",
    "prickly-pear",
    "pelargonium",
    "wisteria",
    "climbing-rose",
    "hydrangea-bush",
    "hydrangea-bush-seed-<seed>",
    "hydrangea-bush-medium",
    "hydrangea-bush-far",
    "hydrangea-tree",
    "agapanthus",
    "star-jasmine",
    "pelargonium-lifecycle-0",
    "pelargonium-lifecycle-1",
    "pelargonium-lifecycle-2",
    "pelargonium-lifecycle-3",
    "pelargonium-lifecycle-4",
    "pelargonium-lifecycle-5",
    "pelargonium-lifecycle-6",
    "pelargonium-lifecycle-7",
    "pelargonium-lifecycle-8",
    "pelargonium-lifecycle-9",
    "pelargonium-lifecycle-10",
    "pelargonium-lifecycle-11",
    "pelargonium-lifecycle-12",
    "pelargonium-lifecycle-13",
    "pelargonium-lifecycle-14",
    "pelargonium-lifecycle-15",
    "pelargonium-lifecycle100-<0..99>",
    "young",
    "medium",
    "far",
    "constrained",
}
CAPTURE_FLOWER_GENERATOR_TARGETS := [?]string {
    "gallery",
    "lifecycle",
    "rounded",
    "pointed",
    "notched",
    "strap",
    "ovate",
    "spatulate",
    "lanceolate",
    "spiral",
    "double",
    "bud",
    "opening",
    "half-open",
    "bloom",
    "fruit-set",
    "immature",
    "ripening",
    "ripe",
}
CAPTURE_WINDOW_GENERATOR_TARGETS := [?]string {
    "gallery",
    "interiors",
    "interiors-day",
    "purpose-gallery",
    "purpose-gallery-day",
    "room-review",
    "room-review-day",
    "room-review-shop",
    "room-review-workshop",
    "room-review-storehouse",
    "room-review-civic",
    "room-review-clinic",
    "dwelling",
    "shop",
    "workshop",
    "storehouse",
    "civic",
    "clinic",
    "adriatic-solid",
    "adriatic-louvered",
    "adriatic-persiana",
    "aegean-solid",
    "aegean-louvered",
    "closed",
    "ajar",
    "open",
}
CAPTURE_FOUNTAIN_GENERATOR_TARGETS := [?]string{"tiered", "bowl", "courtyard"}
CAPTURE_BRIDGE_GENERATOR_TARGETS := [?]string {
    "dalmatian",
    "herzegovinian",
    "venetian",
    "rialto",
    "cycladic",
    "fortress",
    "timber",
    "iron",
}
CAPTURE_CEMETERY_GENERATOR_TARGETS := [?]string {
    "mediterranean",
    "adriatic-medieval",
    "classical-aegean",
    "churchyard",
    "memorial-garden",
    "obelisk",
    "cross",
    "stele",
    "shrine",
    "markers",
    "markers-adriatic",
    "markers-aegean",
    "markers-churchyard",
    "markers-garden",
    "dense",
    "sparse",
    "large",
}
CAPTURE_WINDMILL_GENERATOR_TARGETS := [?]string {
    "adriatic",
    "adriatic-alt",
    "adriatic-crosswind",
    "adriatic-calm",
    "adriatic-storm",
    "aegean",
    "aegean-alt",
    "aegean-crosswind",
    "aegean-calm",
    "aegean-storm",
    "aegean-ten",
    "aegean-twelve",
}
CAPTURE_HERO_BUILDING_TARGETS := [?]string {
    "post-office",
    "compact",
    "grand",
    "clock",
    "mailboxes",
    "airport",
    "airport-compact",
    "airport-grand",
    "clinic",
    "clinic-split",
    "clinic-side",
    "clinic-twin",
    "clinic-compact",
    "clinic-grand",
}
CAPTURE_EDITOR_TARGETS := [?]string{"dunes", "dunes-west", "dunes-blowout", "rock-tool", "plant-stamp", "road-tool"}
CAPTURE_MAP_TARGETS := [?]string{"world-map", "world-map-weather", "dunes", "dunes-west", "dunes-blowout"}
CAPTURE_LIGHTHOUSE_TARGETS := [?]string {
    "adriatic",
    "aegean",
    "night",
    "adriatic-night",
    "aegean-night",
    "reflection-night",
    "short",
    "tall",
}

capture_targets :: proc(kind: Capture_Kind) -> []string {
    #partial switch kind {
    case .Foliage:
        return CAPTURE_FOLIAGE_TARGETS[:]
    case .Foliage_Forest:
        return CAPTURE_FOLIAGE_FOREST_TARGETS[:]
    case .Editor:
        return CAPTURE_EDITOR_TARGETS[:]
    case .Map:
        return CAPTURE_MAP_TARGETS[:]
    case .Building:
        return CAPTURE_BUILDING_TARGETS[:]
    case .Story_Meeting:
        return CAPTURE_STORY_MEETING_TARGETS[:]
    case .Flight:
        return CAPTURE_FLIGHT_TARGETS[:]
    case .Car:
        return CAPTURE_CAR_TARGETS[:]
    case .Mouse_Gait_Lab:
        return CAPTURE_MOUSE_GAIT_TARGETS[:]
    case .Patio_Lab:
        return CAPTURE_PATIO_TARGETS[:]
    case .Garden_Lab:
        return CAPTURE_GARDEN_TARGETS[:]
    case .Plant_Generator_Lab:
        return CAPTURE_PLANT_GENERATOR_TARGETS[:]
    case .Flower_Generator_Lab:
        return CAPTURE_FLOWER_GENERATOR_TARGETS[:]
    case .Window_Generator_Lab:
        return CAPTURE_WINDOW_GENERATOR_TARGETS[:]
    case .Bridge_Generator_Lab:
        return CAPTURE_BRIDGE_GENERATOR_TARGETS[:]
    case .Fountain_Generator_Lab:
        return CAPTURE_FOUNTAIN_GENERATOR_TARGETS[:]
    case .Cemetery_Generator_Lab:
        return CAPTURE_CEMETERY_GENERATOR_TARGETS[:]
    case .Windmill_Generator_Lab:
        return CAPTURE_WINDMILL_GENERATOR_TARGETS[:]
    case .Hero_Building_Lab:
        return CAPTURE_HERO_BUILDING_TARGETS[:]
    case .Lighthouse_Lab:
        return CAPTURE_LIGHTHOUSE_TARGETS[:]
    case .Rainbow_Lab:
        return CAPTURE_RAINBOW_TARGETS[:]
    case .Boat_Lab:
        return CAPTURE_BOAT_LAB_TARGETS[:]
    case .Sky_Noon, .Sky_Sunrise, .Sky_Sunset, .Sky_Storm, .Sky_Night:
        return CAPTURE_SKY_TARGETS[:]
    }
    return nil
}

// Keep foliage as two public capture modes. The specialized enum values remain
// implementation details so old command lines can continue to resolve.
capture_foliage_target_kind :: proc(kind: Capture_Kind, target: string) -> (Capture_Kind, bool) {
    #partial switch kind {
    case .Foliage:
        switch target {
        case "", "overview":
            return .Foliage, true
        case "stress":
            return .Foliage_Stress, true
        case "field":
            return .Foliage, true
        }
    case .Foliage_Forest:
        switch target {
        case "", "canopy":
            return .Foliage_Forest, true
        case "low":
            return .Foliage_Forest_Low, true
        case "understory":
            return .Foliage_Understory, true
        case "golden":
            return .Foliage_Golden, true
        case "wind-a":
            return .Foliage_Wind_A, true
        case "wind-b":
            return .Foliage_Wind_B, true
        case "low-wind-a":
            return .Foliage_Low_Wind_A, true
        case "low-wind-b":
            return .Foliage_Low_Wind_B, true
        }
    }
    return kind, false
}

capture_kind_from_name :: proc(name: string) -> (Capture_Kind, bool) {
    switch name {
    case "editor":
        return .Editor, true
    case "formation":
        return .Formation, true
    case "map":
        return .Map, true
    case "flight":
        return .Flight, true
    case "car":
        return .Car, true
    case "vehicle-showcase":
        return .Vehicle_Showcase, true
    case "paint-mode":
        return .Paint_Mode, true
    case "road":
        return .Road, true
    case "road-dust":
        return .Road_Dust, true
    case "road-grip":
        return .Road_Grip, true
    case "terrain-grip":
        return .Terrain_Grip, true
    case "building":
        return .Building, true
    case "story-meeting":
        return .Story_Meeting, true
    case "foliage":
        return .Foliage, true
    case "foliage-forest":
        return .Foliage_Forest, true
    case "foliage-forest-low":
        return .Foliage_Forest_Low, true
    case "foliage-understory":
        return .Foliage_Understory, true
    case "foliage-forest-golden":
        return .Foliage_Golden, true
    case "foliage-forest-wind-a":
        return .Foliage_Wind_A, true
    case "foliage-forest-wind-b":
        return .Foliage_Wind_B, true
    case "foliage-forest-low-wind-a":
        return .Foliage_Low_Wind_A, true
    case "foliage-forest-low-wind-b":
        return .Foliage_Low_Wind_B, true
    case "foliage-stress":
        return .Foliage_Stress, true
    case "grass-wind":
        return .Grass_Wind, true
    case "witch", "witch-lab":
        return .Witch_Lab, true
    case "screen-pops", "screen-pops-lab":
        return .Screen_Pops_Lab, true
    case "wildflower-lab":
        return .Wildflower_Lab, true
    case "rainbow-lab":
        return .Rainbow_Lab, true
    case "shadow-lab":
        return .Shadow_Lab, true
    case "rock-lab":
        return .Rock_Lab, true
    case "boat-lab":
        return .Boat_Lab, true
    case "boid-lab":
        return .Boid_Lab, true
    case "car-generator-lab":
        return .Car_Generator_Lab, true
    case "patio-lab":
        return .Patio_Lab, true
    case "garden-lab":
        return .Garden_Lab, true
    case "plant-generator":
        return .Plant_Generator_Lab, true
    case "plant-generator-lab":
        return .Plant_Generator_Lab, true
    case "leaf-generator":
        return .Leaf_Generator_Lab, true
    case "leaf-generator-lab":
        return .Leaf_Generator_Lab, true
    case "flower-generator":
        return .Flower_Generator_Lab, true
    case "flower-generator-lab":
        return .Flower_Generator_Lab, true
    case "window-generator", "window-generator-lab":
        return .Window_Generator_Lab, true
    case "bridge-generator", "bridge-generator-lab":
        return .Bridge_Generator_Lab, true
    case "fountain-generator", "fountain-generator-lab":
        return .Fountain_Generator_Lab, true
    case "umbrella-generator", "umbrella-generator-lab":
        return .Umbrella_Generator_Lab, true
    case "cemetery-generator", "cemetery-generator-lab", "graveyard-generator", "graveyard-generator-lab":
        return .Cemetery_Generator_Lab, true
    case "estuary-delta", "estuary-delta-lab":
        return .Estuary_Delta_Lab, true
    case "coastal-ecology",
         "coastal-ecology-lab",
         "coast-generator",
         "rocky-beach",
         "rocky-beach-lab",
         "tidepool",
         "tidepool-lab":
        return .Rocky_Beach_Lab, true
    case "windmill-generator", "windmill-generator-lab":
        return .Windmill_Generator_Lab, true
    case "hero-building", "hero-building-lab", "post-office-generator", "post-office-generator-lab":
        return .Hero_Building_Lab, true
    case "lighthouse-lab":
        return .Lighthouse_Lab, true
    case "mouse-gait-lab":
        return .Mouse_Gait_Lab, true
    case "mouse-theater":
        return .Mouse_Theater, true
    case "rondine-movement-lab":
        return .Rondine_Movement_Lab, true
    case "aircraft-transform", "aircraft-transform-lab":
        return .Aircraft_Transform_Lab, true
    case "markov-wreck":
        return .Markov_Wreck, true
    case "markov-marina":
        return .Markov_Marina, true
    case "markov-farmland":
        return .Markov_Farmland, true
    case "foliage-transition":
        return .Foliage_Transition_Lab, true
    case "ruins", "ruins-lab":
        return .Ruins_Lab, true
    case "markov-town":
        return .Markov_Town, true
    case "markov-city":
        return .Markov_City, true
    case "markov-village":
        return .Markov_Village, true
    case "aegean-city":
        return .Aegean_City, true
    case "aegean-town":
        return .Aegean_Town, true
    case "aegean-village":
        return .Aegean_Village, true
    case "narrow":
        return .Narrow, true
    case "compact":
        return .Compact, true
    case "sky-noon":
        return .Sky_Noon, true
    case "sky-sunrise":
        return .Sky_Sunrise, true
    case "sky-sunset":
        return .Sky_Sunset, true
    case "sky-storm":
        return .Sky_Storm, true
    case "sky-night":
        return .Sky_Night, true
    }
    if len(name) >= 6 && name[:6] == "player" do return .Map, true
    return .None, false
}

// Compatibility adapter for existing editor scripts using private capture flags.
capture_kind_from_arg :: proc(arg: string) -> Capture_Kind {
    if arg == "--capture" do return .Formation
    if len(arg) <= 10 || arg[:10] != "--capture-" do return .None
    kind, ok := capture_kind_from_name(arg[10:])
    return ok ? kind : .None
}
