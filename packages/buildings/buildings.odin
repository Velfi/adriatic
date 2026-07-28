package buildings

// Stable product-level identity for generated architecture. Geometry and
// presentation policy live in the architecture and renderer packages; terrain
// only persists this compact value alongside the generic structure.
Archetype :: enum u8 {
    Legacy,
    Dwelling,
    Townhouse,
    Shop_House,
    Workshop,
    Farmstead,
    Barn_Granary,
    Mill,
    Fishery,
    Storehouse,
    Campanile,
    Palace_Loggia,
    Church,
    Monastery,
    Fortress_Gate,
    Harbor_Office,
    Market_Hall,
    Cycladic_Bell,
    // Appended to preserve the serialized values of established archetypes.
    Mixed_Use_Dwelling,
    Post_Office,
}

Purpose :: enum u8 {
    Dwelling,
    Farmstead,
    Barn_Granary,
    Workshop,
    Inn_Shop,
    Mill,
    Fishery,
    Storehouse,
}

Region :: enum u8 {
    Adriatic,
    Aegean,
}

Landmark_Kind :: enum u8 {
    None,
    Campanile,
    Palace_Loggia,
    Church,
    Monastery,
    Fortress_Gate,
    Harbor_Office,
    Market_Hall,
    Cycladic_Bell,
    // Appended to preserve the serialized values of established landmarks.
    Post_Office,
}

Identity :: struct {
    archetype:     Archetype,
    purpose:       Purpose,
    region:        Region,
    landmark_kind: Landmark_Kind,
}

is_landmark :: proc(identity: Identity) -> bool {
    return(
        identity.landmark_kind != .None ||
        (identity.archetype >= .Campanile && identity.archetype <= .Cycladic_Bell) \
    )
}

is_habitable :: proc(archetype: Archetype) -> bool {
    switch archetype {
    case .Legacy,
         .Dwelling,
         .Townhouse,
         .Shop_House,
         .Mixed_Use_Dwelling,
         .Farmstead,
         .Palace_Loggia,
         .Church,
         .Monastery,
         .Harbor_Office,
         .Market_Hall,
         .Post_Office:
        return true
    case .Workshop, .Barn_Granary, .Mill, .Fishery, .Storehouse, .Campanile, .Fortress_Gate, .Cycladic_Bell:
        return false
    }
    return true
}
