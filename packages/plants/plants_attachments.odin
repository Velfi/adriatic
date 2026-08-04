package plants

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"

attachment_kind :: proc(species: Species, index: int, maturity: f32) -> Attachment_Kind {
    switch species {
    case .Bougainvillea:
        if maturity > .16 && index % 3 != 0 do return .Flower
        if maturity > .38 && index % 11 == 0 do return .Thorn
    case .Grapevine:
        if maturity > .50 && index % 7 == 0 do return .Fruit
        if index % 5 == 0 do return .Tendril
    case .Lemon, .Pomegranate, .Strawberry_Tree:
        if maturity > .58 && index % 8 == 0 do return .Fruit
        if maturity > .22 && index % 9 == 1 do return .Flower
    case .Almond,
         .Oleander,
         .Lavender,
         .Thyme,
         .Sage,
         .Wisteria,
         .Climbing_Rose,
         .Hydrangea_Bush,
         .Hydrangea_Tree,
         .Agapanthus,
         .Star_Jasmine:
        if maturity > .22 && index % 4 == 0 do return .Flower
    case .Pelargonium:
        if maturity > .18 && index % 3 == 0 do return .Flower
    case .Fig, .Olive, .Carob, .Myrtle, .Mastic:
        if maturity > .68 && index % 12 == 0 do return .Fruit
    case .Prickly_Pear:
        // Keep the first, ground-level cladode as a pad; fruit belongs on
        // later joints near the outer edge of the clump.
        if maturity > .68 && index % 12 == 7 do return .Fruit
    case .Bay_Laurel:
        if maturity > .68 && index % 14 == 0 do return .Flower
    case .Italian_Cypress,
         .Rosemary,
         .Stone_Pine,
         .Holm_Oak,
         .Oriental_Plane,
         .European_Hackberry,
         .White_Poplar,
         .Golden_Barrel,
         .Agave,
         .Aloe,
         .Aeonium,
         .Echeveria,
         .Jade_Plant,
         .Stonecrop,
         .Blue_Chalk_Sticks,
         .Golden_Torch_Cactus:
    }
    return .Leaf
}

generated_attachment_kind :: proc(
    species: Species,
    seed: u64,
    index: int,
    maturity: f32,
    detail: Detail_Level,
    depth: int,
) -> Attachment_Kind {
    if species == .Thyme {
        return depth == -8 && maturity > .32 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Lavender {
        return depth == -7 && maturity > .35 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Sage {
        return depth == -6 && maturity > .35 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Agapanthus {
        return depth == -5 && maturity > .42 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Oleander {
        return depth == -9 && maturity > .48 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Wisteria {
        return depth == -10 && maturity > .36 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Climbing_Rose {
        return depth == -11 && maturity > .32 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Carob {
        return depth == -13 && maturity > .68 && detail != .Far ? .Fruit : .Leaf
    }
    if species == .Strawberry_Tree {
        if depth != -12 || detail == .Far do return .Leaf
        hash := (seed + 1) * 0x9e3779b97f4a7c15 ~ u64(index + 61) * 0xbf58476d1ce4e5b9
        if maturity > .62 && hash % 3 != 0 do return .Fruit
        return maturity > .30 ? .Flower : .Leaf
    }
    if species == .Lemon {
        if detail == .Far {
            // At far detail every anchor is silhouette-critical. Fruit and
            // blossom geometry is sub-pixel here and must not replace the
            // broad leaf surrogates retained for that shoot.
            return .Leaf
        }
        // Citrus flowers and fruit belong on newer outer growth. Hashing the
        // stable seed/index pair avoids the regular modulo bands produced by
        // catalog attachment_kind while keeping captures deterministic.
        if depth >= 2 {
            hash := (seed + 1) * 0x9e3779b97f4a7c15 ~ u64(index + 11) * 0xbf58476d1ce4e5b9
            hash = (hash ~ (hash >> 29)) * 0x94d049bb133111eb
            if maturity > .58 && hash % 11 == 0 do return .Fruit
            if maturity > .22 && hash % 13 == 1 do return .Flower
        }
        return .Leaf
    }
    if species == .Pomegranate {
        if detail == .Far do return .Leaf
        // Pomegranate flowers and fruit hang from current outer shoots. The
        // catalog-wide modulo assignment put many replacements inside the
        // dense basal vase, making mature fruit disappear from normal views.
        if depth >= 1 {
            hash := (seed + 1) * 0xbf58476d1ce4e5b9 ~ u64(index + 19) * 0x94d049bb133111eb
            hash = (hash ~ (hash >> 31)) * 0x9e3779b97f4a7c15
            if maturity > .58 && hash % 9 == 0 do return .Fruit
            if maturity > .22 && hash % 11 == 1 do return .Flower
        }
        return .Leaf
    }
    if species == .Hydrangea_Bush || species == .Hydrangea_Tree {
        // Dedicated hydrangea architectures reserve this depth exclusively for
        // terminal mopheads. Interior nodes always retain their paired leaves.
        return depth == -9 && maturity > .22 ? .Flower : .Leaf
    }
    if species == .Italian_Cypress && detail == .Near && maturity >= .78 && depth == 1 {
        // Mature Mediterranean cypresses carry sparse spherical woody cones
        // inside lateral sprays. Hashing seed and anchor index avoids regular
        // bands while keeping placement exact and deterministic. A second
        // hash gives every candidate a stable ripening threshold so cones set
        // progressively instead of all appearing at 78% maturity.
        hash := u64(index + 1) * 0x9e3779b97f4a7c15 + seed * 0xbf58476d1ce4e5b9
        if hash % 29 == 0 {
            cone_set := clamp((maturity - .78) / .18, f32(0), f32(1))
            ripening_hash := (hash ~ (hash >> 27) ~ (seed + 1) * 0x94d049bb133111eb) * 0xbf58476d1ce4e5b9
            if f32(ripening_hash % 10_000) < cone_set * 10_000 do return .Fruit
        }
    }
    if species == .Pelargonium {
        return depth == -4 ? .Flower : .Leaf
    }
    if species == .Star_Jasmine {
        if detail == .Far || maturity <= .22 do return .Leaf
        // White pinwheels need a richer, irregular distribution to remain
        // legible against the sunlit support wall. Avoid modulo rows shared
        // by matching stations on adjacent canes.
        hash := (seed + 1) * 0x9e3779b97f4a7c15 ~ u64(index + 47) * 0xbf58476d1ce4e5b9
        hash = (hash ~ (hash >> 29)) * 0x94d049bb133111eb
        return hash % 3 == 0 ? .Flower : .Leaf
    }
    return attachment_kind(species, index, maturity)
}

leaf_traits :: proc(species: Species, variant: u8, maturity: f32) -> Leaf_Traits {
    traits: Leaf_Traits
    switch species {
    case .Olive:
        // Olea europaea leaves reach about 7.5 cm; use the mature upper bound
        // rather than a canopy-coverage surrogate.
        traits = {.Lanceolate, .075, .020, 0, .006, .0025, 0}
    case .Italian_Cypress:
        // Represent overlapping scale-leaf sprays rather than individual
        // microscopic scales; the latter disappear at ordinary game-camera
        // distances and expose the procedural scaffold.
        // Favor slim shoot-following fans over broad pads. The longer axis
        // bridges neighboring anchors, while the reduced width prevents the
        // crown from resolving into stacked rounded topiary lobes.
        traits = {.Cypress_Spray, .078, .032, 0, .013, .0045, 0}
    case .Grapevine:
        traits = {.Grapevine, .18, .16, .05, .016, .008, 0}
    case .Fig:
        traits = {.Fig, .21, .185, 0, .017, .010, 0}
    case .Lemon:
        // Citrus leaves are broad, but the old footprint let neighboring
        // alternate shoots overlap into a wall of flat cards at near detail.
        // Keep the elliptic silhouette while restoring visible twig and fruit
        // gaps through the crown.
        traits = {.Elliptic, .145, .062, .04, .011, .005, 0}
    case .Pomegranate:
        // Punica granatum leaves are typically 2.5-10 cm long.
        traits = {.Lanceolate, .100, .034, 0, .007, .0035, 0}
    case .Almond:
        traits = {.Lanceolate, .15, .048, .08, .010, .004, 0}
    case .Oleander:
        traits = {.Lanceolate, .18, .035, 0, .012, .004, 0}
    case .Bougainvillea:
        traits = {.Ovate, .13, .090, 0, .014, .006, 0}
    case .Rosemary:
        traits = {.Lanceolate, .034, .004, 0, .005, .0008, 0}
    case .Stone_Pine:
        // Generate an open fascicle instead of substituting a broad leaf.
        traits = {.Pine_Needle_Clump, .135, .090, 0, .018, .0028, 0}
    case .Bay_Laurel:
        traits = {.Lanceolate, .16, .052, .04, .014, .006, 0}
    case .Carob:
        traits = {.Elliptic, .105, .066, 0, .008, .006, 0}
    case .Strawberry_Tree:
        traits = {.Elliptic, .13, .055, .11, .012, .005, 0}
    case .Myrtle:
        traits = {.Lanceolate, .075, .025, 0, .008, .003, 0}
    case .Mastic:
        traits = {.Elliptic, .072, .031, 0, .007, .003, 0}
    case .Lavender:
        // English lavender leaves are about 1-2.5 cm long.
        traits = {.Lanceolate, .025, .006, 0, .004, .0012, 0}
    case .Thyme:
        // Common thyme leaves are roughly 6-13 mm long.
        // One rendered blade represents a close opposite pair so the mat
        // remains legible at gameplay distance without enlarging its crown.
        traits = {.Ovate, .024, .012, 0, .0035, .0012, 0}
    case .Sage:
        traits = {.Ovate, .105, .055, .12, .018, .012, 0}
    case .Prickly_Pear:
        // The grammar already builds a multi-generation clump. Metre-scale
        // presentation of the old .48 pad stacked those generations into a
        // hedge; a compact cladode keeps joints and stepped tiers readable.
        traits = {.Ovate, .36, .21, 0, .016, .045, .070}
    case .Pelargonium:
        // Broad, nearly round and shallowly scalloped: this silhouette is the
        // strongest distinction between pelargonium and a generic shrub.
        traits = {.Lobed, .090, .082, .032, .013, .007, 0}
    case .Wisteria:
        traits = {.Elliptic, .105, .052, 0, .010, .004, 0}
    case .Climbing_Rose:
        traits = {.Ovate, .105, .062, .08, .012, .006, 0}
    case .Hydrangea_Bush, .Hydrangea_Tree:
        // Hydrangea leaves are broad ovates rather than long lance-like
        // blades. A near-square footprint keeps isolated crown-edge leaves
        // from projecting as spears while retaining their coarse silhouette.
        traits = {.Ovate, .158, .136, .12, .022, .012, 0}
    case .Agapanthus:
        traits = {.Lanceolate, .31, .030, 0, .020, .006, 0}
    case .Star_Jasmine:
        traits = {.Elliptic, .080, .043, 0, .009, .004, 0}
    case .Holm_Oak:
        traits = {.Ovate, .125, .068, .10, .013, .007, 0}
    case .Oriental_Plane:
        traits = {.Lobed, .19, .17, .06, .018, .008, 0}
    case .European_Hackberry:
        traits = {.Ovate, .105, .052, .12, .012, .005, 0}
    case .White_Poplar:
        traits = {.Deltoid, .115, .105, .08, .014, .007, 0}
    case .Golden_Barrel:
        // One narrow, deeply cupped blade reads as a single vertical rib;
        // the radial architecture closes those ribs into a squat barrel.
        traits = {.Lanceolate, .42, .075, 0, .010, .055, .060}
    case .Agave:
        traits = {.Lanceolate, .58, .115, .06, .040, .045, .038}
    case .Aloe:
        traits = {.Lanceolate, .44, .055, .10, .060, .028, .026}
    case .Aeonium:
        traits = {.Ovate, .22, .105, 0, .018, .020, .026}
    case .Echeveria:
        traits = {.Ovate, .20, .115, 0, .026, .028, .034}
    case .Jade_Plant:
        traits = {.Ovate, .105, .072, 0, .008, .022, .030}
    case .Stonecrop:
        traits = {.Ovate, .038, .024, 0, .007, .012, .018}
    case .Blue_Chalk_Sticks:
        traits = {.Lanceolate, .24, .024, 0, .010, .012, .020}
    case .Golden_Torch_Cactus:
        traits = {.Lanceolate, .78, .080, 0, .006, .040, .052}
    }
    variation := .92 + f32(variant) * .055
    maturity_scale := .72 + clamp(maturity, f32(0), f32(1)) * .28
    traits.length *= variation * maturity_scale
    traits.width *= (1.04 - f32(variant) * .025) * maturity_scale
    traits.curl *= variant % 2 == 0 ? f32(1) : f32(-1)
    return traits
}

generated_leaf_traits :: proc(species: Species, variant: u8, maturity: f32, detail: Detail_Level) -> Leaf_Traits {
    traits := leaf_traits(species, variant, maturity)
    if species == .Italian_Cypress {
        // Reduced tiers represent whole overlapping scale-leaf sprays. Their
        // footprint grows as geometry falls so the distant crown converges
        // toward a solid silhouette instead of exposing individual twigs.
        length_scale := detail == .Far ? f32(2.05) : detail == .Medium ? f32(1.10) : f32(1)
        width_scale := detail == .Far ? f32(3.5) : detail == .Medium ? f32(2.2) : f32(1)
        traits.length *= length_scale
        traits.width *= width_scale
        traits.curl *= length_scale
        traits.cup *= width_scale
    }
    if species == .Olive {
        // With opposite pairs collapsed from two leaves to one at far detail,
        // treat the survivor as a small spray surrogate. Width grows more
        // than length so distant foliage fills crown mass instead of becoming
        // a set of longer fern-like strokes.
        length_scale := detail == .Far ? f32(1.60) : detail == .Medium ? f32(1.14) : f32(1)
        width_scale := detail == .Far ? f32(3.00) : detail == .Medium ? f32(1.28) : f32(1)
        traits.length *= length_scale
        traits.width *= width_scale
        traits.curl *= length_scale
        traits.cup *= width_scale
    }
    if species == .Lemon {
        // Reduced tiers collapse whole glossy citrus sprays into a few
        // anchors. Broaden those survivors into canopy surrogates so the
        // radial scaffold does not reappear as a bare candelabra.
        length_scale := detail == .Far ? f32(1.90) : detail == .Medium ? f32(1.12) : f32(1)
        width_scale := detail == .Far ? f32(3.20) : detail == .Medium ? f32(1.35) : f32(1)
        traits.length *= length_scale
        traits.width *= width_scale
        traits.curl *= length_scale
        traits.cup *= width_scale
    }
    return traits
}

attachment_frame :: proc(
    forward, up: plant_structure.Vec3,
    profile: Profile,
    climbing: bool,
) -> (
    result_forward, result_up: plant_structure.Vec3,
) {
    result_forward = {
        forward[0] * profile.width_scale,
        forward[1] * profile.height_scale,
        forward[2] * profile.width_scale,
    }
    result_up = {up[0] * profile.width_scale, up[1] * profile.height_scale, up[2] * profile.width_scale}
    if climbing {
        result_forward[2] = 0
        if linalg.dot(result_forward, result_forward) < .001 do result_forward = {0, 1, 0}
        result_forward = linalg.normalize0(result_forward)
        result_up = {0, 0, 1}
        return
    }
    result_forward = linalg.normalize0(result_forward)
    if linalg.dot(result_forward, result_forward) < .001 do result_forward = {0, 1, 0}
    // Gram-Schmidt keeps up perpendicular after non-uniform species scaling.
    result_up -= result_forward * linalg.dot(result_up, result_forward)
    result_up = linalg.normalize0(result_up)
    if linalg.dot(result_up, result_up) < .001 {
        reference := math.abs(result_forward[1]) < .9 ? plant_structure.Vec3{0, 1, 0} : plant_structure.Vec3{1, 0, 0}
        right := linalg.normalize0(linalg.cross(result_forward, reference))
        result_up = linalg.normalize0(linalg.cross(right, result_forward))
    }
    return
}

on_left_return_wall :: proc(position: plant_structure.Vec3, support: ^Support_Surface) -> bool {
    return_plane_x := support != nil ? support.left_corner_x + support.plane_z : f32(0)
    return(
        support != nil &&
        support.left_return_depth > 0 &&
        position[2] > support.plane_z + .001 &&
        math.abs(position[0] - return_plane_x) < .02 \
    )
}

fold_source_attachment_frame :: proc(forward, up: ^plant_structure.Vec3, position: plant_structure.Vec3, support: ^Support_Surface) {
    if !on_left_return_wall(position, support) do return
    // Unwrapped negative x becomes positive z after folding around the left
    // corner. Rotate the already-scaled front-wall frame by ninety degrees.
    forward^ = linalg.normalize0(plant_structure.Vec3{0, forward^[1], -forward^[0]})
    if linalg.dot(forward^, forward^) < .001 do forward^ = {0, 1, 0}
    up^ = {1, 0, 0}
}

routed_attachment_frame :: proc(
    direction, position: plant_structure.Vec3,
    support: ^Support_Surface,
) -> (
    forward, up: plant_structure.Vec3,
) {
    if on_left_return_wall(position, support) {
        forward = linalg.normalize0(plant_structure.Vec3{0, direction[1], direction[2]})
        if linalg.dot(forward, forward) < .001 do forward = {0, 1, 0}
        up = {1, 0, 0}
        return
    }
    forward = linalg.normalize0(plant_structure.Vec3{direction[0], direction[1], 0})
    if linalg.dot(forward, forward) < .001 do forward = {0, 1, 0}
    up = {0, 0, 1}
    return
}

update_leaf_bounds :: proc(bounds: ^Bounds, position, forward, up: plant_structure.Vec3, traits: Leaf_Traits, first: ^bool) {
    right := linalg.normalize0(linalg.cross(forward, up))
    if linalg.dot(right, right) < .001 do right = {1, 0, 0}
    half_width := traits.width * .5
    lift := math.abs(traits.curl) + math.abs(traits.cup)
    stations := [2]plant_structure.Vec3{position, position + forward * traits.length}
    sides := [2]f32{-1, 1}
    for station in stations {
        for side in sides {
            update_bounds(bounds, station + right * half_width * side + up * lift, first)
            update_bounds(bounds, station + right * half_width * side - up * lift, first)
        }
    }
}

route_point :: proc(
    point: plant_structure.Vec3,
    support: ^Support_Surface,
    source_height, source_half_width: f32,
    habit: Growth_Habit,
    depth: int,
) -> plant_structure.Vec3 {
    result := point
    height_fraction := clamp(point[1] / max(source_height, f32(.001)), f32(0), f32(1))
    root_x := clamp(support.root_x, -support.width * .46, support.width * .46)
    opposite_x := root_x <= 0 ? support.width * .42 : -support.width * .42
    folded_left_wall := habit == .Wall_Trained && support.left_return_depth > 0 && support.left_corner_x < root_x
    route_min_x := -support.width * .48
    if folded_left_wall do route_min_x = support.left_corner_x - support.left_return_depth
    if habit == .Trellised && depth <= -20 {
        normalized_x := clamp(point[0] / max(source_half_width, f32(.001)), f32(-1), f32(1))
        if math.abs(root_x) > support.width * .20 {
            // End-planted vines train one long cordon across the support.
            // Preserve the trunk at the authored centre while mapping cordon
            // and fruiting-shoot positions through the full root-to-end span.
            if depth == -23 {
                result[0] = root_x
            } else {
                fraction := (normalized_x + 1) * .5
                result[0] = root_x + (opposite_x - root_x) * fraction
            }
        } else {
            result[0] = root_x + normalized_x * support.width * .42
        }
        result[0] = clamp(result[0], route_min_x, support.width * .48)
        result[1] = height_fraction * support.height * .92
        // Ties and wire hold grape canes slightly proud of the wall. Keeping
        // them exactly coplanar causes alternating spans to lose the depth
        // test and appear as disconnected dashes in the lab.
        result[2] = support.plane_z + .16
        for exclusion in support.exclusions {
            if result[0] < exclusion.minimum_x ||
               result[0] > exclusion.maximum_x ||
               result[1] < exclusion.minimum_y ||
               result[1] > exclusion.maximum_y {
                continue
            }
            margin := f32(.12)
            // Preserve a continuous root-side route around openings. Stable
            // side choice prevents neighboring phytomer anchors from
            // alternating across a window and drawing canes through it.
            exclusion_center := (exclusion.minimum_x + exclusion.maximum_x) * .5
            if root_x <= exclusion_center {
                result[0] = exclusion.minimum_x - margin
            } else {
                result[0] = exclusion.maximum_x + margin
            }
            result[0] = clamp(result[0], route_min_x, support.width * .48)
        }
        return result
    }
    // Source x is the botanical left/right axis: opposing yaw branches must
    // remain opposing when flattened onto the wall. Depth contributes only a
    // small offset to separate shoots that would otherwise overlap. Giving
    // both axes equal weight made similarly pitched left and right canes
    // inherit the same z sign and collapse onto one side of the support.
    lateral_source := point[0] + point[2] * .18
    lateral_fraction := clamp(lateral_source / max(source_half_width, f32(.001)), f32(-1), f32(1))
    // Projection must be a function of source position alone. Parent ends and
    // child starts share a botanical point but have different depths; using
    // depth here pulled those identical junctions apart into floating tufts.
    branch_order := math.abs(lateral_fraction) * 3
    spread_envelope := .16 + height_fraction * .84
    lateral_spread := lateral_fraction * support.width * (.25 + branch_order * .055) * spread_envelope
    // Keep the leader near its root with a slow searching meander, then let
    // lateral and secondary shoots use the source plant's two horizontal
    // axes to fan across the available surface.
    leader_meander :=
        f32(math.sin(f64(height_fraction * math.PI * 2.35 + lateral_fraction * .71))) *
        support.width *
        (.035 + branch_order * .010) *
        spread_envelope
    // Wall-trained growth must not inherit a shared destination from the
    // root's position. That global opposite-side drift overpowered negative
    // lateral axes and bent every plant toward the same end of the wall.
    result[0] = root_x + lateral_spread + leader_meander
    result[1] = height_fraction * support.height * .96
    result[2] = support.plane_z
    result[0] = clamp(result[0], route_min_x, support.width * .48)
    if habit == .Trellised {
        // A trellised vine climbs freely to its first wire, then trains its
        // generated leader and branches along four horizontal tiers. Snapping
        // only the support projection retains botanical
        // branching while removing the unsupported diagonal curtain.
        raw_y := height_fraction * support.height * .96
        first_wire := min(f32(.55), support.height * .22)
        top_wire := support.height * .96
        tier_spacing := (top_wire - first_wire) / 3
        if raw_y < first_wire {
            result[0] = root_x + lateral_spread * .20
            result[1] = raw_y
        } else {
            training_progress := clamp((raw_y - first_wire) / max(top_wire - first_wire, f32(.001)), f32(0), f32(1))
            training_progress = training_progress * training_progress * (3 - 2 * training_progress)
            // Train opposing shoots into bilateral cordons. Choosing one
            // `opposite_x` for a centered root sent the entire grapevine to
            // the right-hand side regardless of its generated branch axis.
            source_angle := f32(math.atan2(f64(point[2]), f64(point[0])))
            trellis_lateral := clamp(source_angle / math.PI, f32(-1), f32(1))
            cordon_reach: f32
            if math.abs(root_x) > support.width * .20 {
                // A vine planted at the end of a trellis trains primarily
                // across it; treating the root as the centre of a bilateral
                // cordon wastes half the support outside the frame.
                reach_fraction := .72 + math.abs(trellis_lateral) * .28
                cordon_reach = (opposite_x - root_x) * reach_fraction * training_progress
            } else {
                cordon_reach = trellis_lateral * support.width * .42 * training_progress
            }
            result[0] = root_x + cordon_reach + lateral_spread * .48
            tier := clamp(int(math.round(f64((raw_y - first_wire) / max(tier_spacing, f32(.001))))), 0, 3)
            wire_y := first_wire + f32(tier) * tier_spacing
            if depth == 0 {
                // Keep the structural leader and cordons trained on wires.
                result[1] = wire_y
            } else {
                // Fruiting shoots grow away from a cordon; snapping their
                // every node and leaf anchor to the same wire created four
                // topiary shelves. Retain most generated height while a mild
                // wire bias keeps the canopy visibly trained.
                result[1] = raw_y * .82 + wire_y * .18
            }
        }
        result[0] = clamp(result[0], route_min_x, support.width * .48)
    }
    for exclusion in support.exclusions {
        exclusion_center := (exclusion.minimum_x + exclusion.maximum_x) * .5
        clearance := max(f32(.18), support.height * .12)
        release_fraction := clamp(exclusion.maximum_y / max(support.height, f32(.001)), f32(0), f32(.98))
        // Planters and low plinths can raise a doorway exclusion slightly;
        // distinguish those from upper windows by relative wall height.
        ground_opening := exclusion.minimum_y <= support.height * .18
        margin := f32(.12)
        root_beneath_opening :=
            !ground_opening && root_x >= exclusion.minimum_x - margin && root_x <= exclusion.maximum_x + margin
        if habit == .Wall_Trained && root_beneath_opening && result[1] <= exclusion.maximum_y + clearance {
            // Establish the fork below the sill instead of waiting until a
            // cane is already level with the glass. By the first window each
            // generated side has reached its own jamb, leaving two readable
            // leaders from the root rather than one diagonal fan.
            // Give the return wall a slight majority of the searching canes.
            // Its foreshortened screen area needs more botanical occupancy
            // than the broad front wall to read as a balanced corner plant.
            route_left := lateral_fraction < .18
            edge_spread := math.abs(lateral_fraction) * support.width * .10
            target_x :=
                route_left ? exclusion.minimum_x - margin - edge_spread : exclusion.maximum_x + margin + edge_spread
            if route_left && folded_left_wall {
                return_fraction := .28 + math.abs(lateral_fraction) * .48
                target_x = support.left_corner_x - support.left_return_depth * return_fraction
            }
            approach_height := max(exclusion.minimum_y * .5, f32(.001))
            approach := clamp(result[1] / approach_height, f32(0), f32(1))
            approach = approach * approach * (3 - 2 * approach)
            result[0] = linalg.lerp(result[0], target_x, approach)
            result[0] = clamp(result[0], route_min_x, support.width * .48)
            continue
        }
        if habit == .Wall_Trained && ground_opening && height_fraction > release_fraction {
            // Train the connected canopy across the lintel while retaining
            // each shoot's authored lateral displacement. Remapping the rise
            // keeps attachment-bearing portions on the wall instead of
            // leaving long bare connectors to isolated roofline tufts.
            canopy_progress := clamp(
                (height_fraction - release_fraction) / max(1 - release_fraction, f32(.001)),
                f32(0),
                f32(1),
            )
            canopy_progress = canopy_progress * canopy_progress * (3 - 2 * canopy_progress)
            // Once above the opening, let each cane's botanical lateral axis
            // establish its own wall route. Driving almost all horizontal
            // travel from height made every shoot climb the jamb first and
            // arrive at the opposite side only along the roofline. A modest
            // shared advance keeps the plant moving away from its root while
            // the independent fan fills the lintel and wall face at several
            // heights.
            shared_advance := .16 + canopy_progress * .52
            independent_fan := lateral_fraction * support.width * (.18 + canopy_progress * .10)
            result[0] = root_x + (opposite_x - root_x) * shared_advance + independent_fan + lateral_spread * .42
            lintel_top := support.height * .96
            result[1] = exclusion.maximum_y + .02 + (lintel_top - exclusion.maximum_y - .02) * canopy_progress
            result[0] = clamp(result[0], route_min_x, support.width * .48)
            continue
        }
        // Hold the routed side for enough vertical distance that a tessellated
        // segment can turn above the opening without its chord cutting back
        // through the exclusion. Once clear, restore each shoot's generated
        // lateral position. Forcing every upper shoot to traverse the lintel
        // from root side to opposite side collapsed a branching canopy into
        // one conspicuous diagonal perimeter stroke.
        if result[1] < exclusion.minimum_y || result[1] > exclusion.maximum_y + clearance {
            continue
        }
        // Keep the vine on the root side while it climbs past an opening.
        // Choosing the nearest edge independently allowed connected segment
        // endpoints to flip sides and draw a branch straight through a door.
        edge_spread := math.abs(lateral_fraction) * support.width * .10
        if root_x <= exclusion_center {
            result[0] = min(result[0], exclusion.minimum_x - margin - edge_spread)
        } else {
            result[0] = max(result[0], exclusion.maximum_x + margin + edge_spread)
        }
        result[0] = clamp(result[0], route_min_x, support.width * .48)
    }
    // Multiple stacked openings may successively influence the same point.
    // Enforce the final clearance after all routing passes so a later window's
    // approach cannot pull a cane back through an earlier pane.
    for exclusion in support.exclusions {
        if result[0] < exclusion.minimum_x ||
           result[0] > exclusion.maximum_x ||
           result[1] < exclusion.minimum_y ||
           result[1] > exclusion.maximum_y {
            continue
        }
        margin := f32(.12)
        exclusion_center := (exclusion.minimum_x + exclusion.maximum_x) * .5
        root_beneath_opening :=
            support.root_x >= exclusion.minimum_x - margin && support.root_x <= exclusion.maximum_x + margin
        route_left := root_beneath_opening ? lateral_fraction < .18 : support.root_x <= exclusion_center
        result[0] = route_left ? exclusion.minimum_x - margin : exclusion.maximum_x + margin
        result[0] = clamp(result[0], route_min_x, support.width * .48)
    }
    if folded_left_wall && result[0] < support.left_corner_x {
        distance_around_corner := min(support.left_corner_x - result[0], support.left_return_depth)
        // Match the front wall's proud offset on the perpendicular plane.
        // Landing directly on the masonry caused the wrapped canopy to lose
        // the depth test and appear as a few intermittent marks at the seam.
        result[0] = support.left_corner_x + support.plane_z
        result[2] = support.plane_z + distance_around_corner
    }
    return result
}

route_species_point :: proc(
    point: plant_structure.Vec3,
    support: ^Support_Surface,
    source_height, source_half_width: f32,
    habit: Growth_Habit,
    depth: int,
    species: Species,
) -> plant_structure.Vec3 {
    routed := route_point(point, support, source_height, source_half_width, habit, depth)
    if species != .Wisteria && species != .Star_Jasmine do return routed

    axis_start, axis_end: plant_structure.Vec3
    if len(support.axes) > 0 {
        normalized_x := clamp(point[0] / max(source_half_width, f32(.001)), f32(-1), f32(1))
        axis_index := clamp(
            int(math.round(f64((normalized_x + 1) * .5 * f32(len(support.axes) - 1)))),
            0,
            len(support.axes) - 1,
        )
        axis_start = support.axes[axis_index].start
        axis_end = support.axes[axis_index].end
    } else {
        // A wall without authored axes receives a deterministic five-rail
        // training lattice. The rails are botanical supports, not visible
        // geometry; masonry-trained twiners still wind instead of becoming a
        // flat fan.
        normalized_x := clamp(point[0] / max(source_half_width, f32(.001)), f32(-1), f32(1))
        rail := clamp(int(math.round(f64((normalized_x + 1) * 2))), 0, 4)
        rail_x := -support.width * .40 + f32(rail) * support.width * .20
        axis_start = {rail_x, 0, support.plane_z}
        axis_end = {rail_x, support.height * .96, support.plane_z}
    }
    axis := axis_end - axis_start
    axis_length_squared := linalg.dot(axis, axis)
    if axis_length_squared < 1e-8 do return routed
    t := clamp(linalg.dot(routed - axis_start, axis) / axis_length_squared, f32(0), f32(1))
    center := axis_start + axis * t
    tangent := linalg.normalize0(axis)
    reference := math.abs(tangent[1]) > .88 ? plant_structure.Vec3{1, 0, 0} : plant_structure.Vec3{0, 1, 0}
    right := linalg.normalize0(linalg.cross(tangent, reference))
    outward := linalg.normalize0(linalg.cross(right, tangent))
    handedness := species == .Wisteria ? f32(-1) : f32(1)
    turns := species == .Wisteria ? f32(4.5) : f32(6.0)
    phase := handedness * (t * turns * math.PI * 2 + point[0] * .7)
    radius := max(support.contact_radius, f32(.035))
    return center + right * math.cos(phase) * radius + outward * math.sin(phase) * radius
}

update_bounds :: proc(bounds: ^Bounds, point: plant_structure.Vec3, first: ^bool) {
    if first^ {
        bounds.minimum = point
        bounds.maximum = point
        first^ = false
        return
    }
    bounds.minimum = linalg.min(bounds.minimum, point)
    bounds.maximum = linalg.max(bounds.maximum, point)
}

finalize_segment_topology :: proc(plant: ^Generated_Plant) {
    if plant == nil do return
    delete(plant.segment_parents)
    delete(plant.segment_axes)
    count := len(plant.segments)
    plant.segment_parents = make([dynamic]int, count)
    plant.segment_axes = make([dynamic]int, count)
    resize(&plant.segment_parents, count)
    resize(&plant.segment_axes, count)
    axis_count := 0
    for segment, segment_index in plant.segments {
        parent := -1
        for candidate_index := segment_index - 1; candidate_index >= 0; candidate_index -= 1 {
            delta := plant.segments[candidate_index].end - segment.start
            if linalg.dot(delta, delta) <= 1e-8 {
                parent = candidate_index
                break
            }
        }
        plant.segment_parents[segment_index] = parent
        if parent >= 0 && plant.segments[parent].depth == segment.depth {
            plant.segment_axes[segment_index] = plant.segment_axes[parent]
        } else {
            plant.segment_axes[segment_index] = axis_count
            axis_count += 1
        }
    }
}

olive_random_signed :: proc(random: ^u64) -> f32 {
    return f32(plant_structure.random_next(random) >> 40) / f32(1 << 24) * 2 - 1
}
