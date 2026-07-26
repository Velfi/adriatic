package main

Capture_Kind :: enum {
    None,
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
    Narrow,
    Compact,
    Sky_Noon,
    Sky_Sunset,
    Sky_Storm,
    Sky_Night,
}

Capture_Request :: struct {
    kind:        Capture_Kind,
    output_path: string,
    target:      string,
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

capture_kind_from_name :: proc(name: string) -> (Capture_Kind, bool) {
    switch name {
    case "formation": return .Formation, true
    case "map": return .Map, true
    case "flight": return .Flight, true
    case "car": return .Car, true
    case "vehicle-showcase": return .Vehicle_Showcase, true
    case "paint-mode": return .Paint_Mode, true
    case "road": return .Road, true
    case "road-dust": return .Road_Dust, true
    case "road-grip": return .Road_Grip, true
    case "terrain-grip": return .Terrain_Grip, true
    case "building": return .Building, true
    case "foliage": return .Foliage, true
    case "foliage-forest": return .Foliage_Forest, true
    case "foliage-forest-low": return .Foliage_Forest_Low, true
    case "foliage-understory": return .Foliage_Understory, true
    case "foliage-forest-golden": return .Foliage_Golden, true
    case "foliage-forest-wind-a": return .Foliage_Wind_A, true
    case "foliage-forest-wind-b": return .Foliage_Wind_B, true
    case "foliage-forest-low-wind-a": return .Foliage_Low_Wind_A, true
    case "foliage-forest-low-wind-b": return .Foliage_Low_Wind_B, true
    case "foliage-stress": return .Foliage_Stress, true
    case "narrow": return .Narrow, true
    case "compact": return .Compact, true
    case "sky-noon": return .Sky_Noon, true
    case "sky-sunset": return .Sky_Sunset, true
    case "sky-storm": return .Sky_Storm, true
    case "sky-night": return .Sky_Night, true
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
