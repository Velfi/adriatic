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
    Wildflower_Lab,
    Shadow_Lab,
    Boat_Lab,
    Mouse_Gait_Lab,
    Rondine_Movement_Lab,
    Markov_Wreck,
    Markov_Farmland,
    Markov_Marina,
    Markov_Town,
    Markov_City,
    Markov_Village,
    Aegean_City,
    Aegean_Town,
    Aegean_Village,
    Narrow,
    Compact,
    Sky_Noon,
    Sky_Sunset,
    Sky_Storm,
    Sky_Night,
}

Capture_Request :: struct {
    kind:          Capture_Kind,
    output_path:   string,
    target:        string,
    window_width:  int,
    window_height: int,
    settle_frames: int,
    camera_eye:          [3]f32,
    camera_look_at:      [3]f32,
    camera_eye_set:      bool,
    camera_look_at_set:  bool,
    camera_orbit_degrees:[2]f32,
    camera_orbit_set:    bool,
    camera_distance:     f32,
    camera_distance_set: bool,
    camera_offset:       [3]f32,
    camera_offset_set:   bool,
}

CAPTURE_SKY_KINDS :: bit_set[Capture_Kind]{.Sky_Noon, .Sky_Sunset, .Sky_Storm, .Sky_Night}
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
CAPTURE_SKY_TARGETS := [?]string{"sun", "sun-air", "sun-away", "moon", "stars"}

capture_targets :: proc(kind: Capture_Kind) -> []string {
    #partial switch kind {
    case .Building:
        return CAPTURE_BUILDING_TARGETS[:]
    case .Flight:
        return CAPTURE_FLIGHT_TARGETS[:]
    case .Sky_Noon, .Sky_Sunset, .Sky_Storm, .Sky_Night:
        return CAPTURE_SKY_TARGETS[:]
    }
    return nil
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
    case "wildflower-lab":
        return .Wildflower_Lab, true
    case "shadow-lab":
        return .Shadow_Lab, true
    case "boat-lab":
        return .Boat_Lab, true
    case "mouse-gait-lab":
        return .Mouse_Gait_Lab, true
    case "rondine-movement-lab":
        return .Rondine_Movement_Lab, true
    case "markov-wreck":
        return .Markov_Wreck, true
    case "markov-marina":
        return .Markov_Marina, true
    case "markov-farmland":
        return .Markov_Farmland, true
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
