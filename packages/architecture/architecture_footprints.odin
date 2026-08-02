package architecture

import circulation "../circulation"
import terrain "../terrain"

Architecture_Mass :: struct {
    local_x, local_z, width, depth, height_scale: f32,
}

Architecture_Footprint :: struct {
    masses: [3]Architecture_Mass,
    count:  int,
}

architecture_footprint :: #force_inline proc(structure: terrain.Structure) -> Architecture_Footprint {
    result: Architecture_Footprint
    result.masses[0] = {0, 0, structure.width, structure.depth, 1}
    result.count = 1
    if structure.kind != .Architecture do return result
    identity := architecture_resolve_legacy_identity(structure)
    archetype := identity.archetype
    variant := structure.seed

    if archetype == .Farmstead && identity.region == .Aegean && structure.width >= 12 && structure.depth >= 12 {
        // Cycladic farmhouses are accretions of compact cells, not a pitched
        // domestic bar with a northern service wing. Step two useful rooms
        // down the contour and leave a yard-facing notch between them.
        side := variant & 1 == 0 ? f32(-1) : f32(1)
        result.masses[0] = {0, structure.depth * .22, structure.width, structure.depth * .56, 1}
        result.masses[1] = {
            side * structure.width * .27,
            -structure.depth * .18,
            max(structure.width * .46, f32(4.5)),
            max(structure.depth * .52, f32(4.5)),
            .72,
        }
        result.count = 2
        if structure.width >= 20 && structure.depth >= 18 && variant % 3 == 0 {
            result.masses[2] = {
                -side * structure.width * .31,
                -structure.depth * .24,
                max(structure.width * .34, f32(4.5)),
                max(structure.depth * .38, f32(4.5)),
                .58,
            }
            result.count = 3
        }
    } else if archetype == .Farmstead &&
       identity.region == .Adriatic &&
       structure.width >= 20 &&
       structure.depth >= 18 &&
       structure.height >= ARCHITECTURE_MIN_OPENING_WALL_HEIGHT / .58 &&
       variant % 5 == 0 {
        // A broad farmhouse gains a lower connected work range rather than
        // sharing every domestic courtyard/L variant. The street bar remains
        // the public house; the offset rear range reads as dairy, washhouse,
        // or tool room while retaining an interior passage.
        result.masses[0] = {0, structure.depth * .20, structure.width, structure.depth * .60, 1}
        result.masses[1] = {
            (variant & 1) == 0 ? -structure.width * .25 : structure.width * .25,
            -structure.depth * .22,
            structure.width * .46,
            structure.depth * .56,
            .58,
        }
        result.count = 2
    } else if (archetype == .Dwelling || (archetype == .Farmstead && identity.region == .Adriatic)) &&
       structure.width >= 26 &&
       structure.depth >= 20 &&
       variant % 8 == 3 {
        // A shallow U around a rear court is reserved for genuinely broad
        // parcels; smaller lots stay legible as houses rather than compounds.
        result.masses[0] = {0, structure.depth * .32, structure.width, max(structure.depth * .36, f32(4.5)), 1}
        result.masses[1] = {
            -structure.width * .36,
            -structure.depth * .08,
            max(structure.width * .28, f32(4.5)),
            max(structure.depth * .64, f32(4.5)),
            .72,
        }
        result.masses[2] = {
            structure.width * .36,
            -structure.depth * .08,
            max(structure.width * .28, f32(4.5)),
            max(structure.depth * .64, f32(4.5)),
            .72,
        }
        result.count = 3
    } else if (archetype == .Dwelling || (archetype == .Farmstead && identity.region == .Adriatic)) &&
       structure.width >= 18 &&
       structure.depth >= 18 &&
       variant % 8 == 6 {
        // T plan: a broad street range with a centered rear range. Unlike the
        // mirrored L plans this reads as a different silhouette from either
        // side and gives medium-width rural parcels a compound option.
        result.masses[0] = {0, structure.depth * .24, structure.width, structure.depth * .52, 1}
        result.masses[1] = {
            0,
            -structure.depth * .19,
            max(structure.width * .44, f32(4.5)),
            max(structure.depth * .62, f32(4.5)),
            .82,
        }
        result.count = 2
    } else if (archetype == .Dwelling || (archetype == .Farmstead && identity.region == .Adriatic)) &&
       structure.width >= 12 &&
       structure.depth >= 14 &&
       variant % 4 == 1 {
        // L plan: a street bar with a shorter rear wing.
        result.masses[0] = {0, structure.depth * .25, structure.width, structure.depth * .5, 1}
        result.masses[1] = {
            // % 4 == 1 fixes bit zero, so use the next variant lane to
            // actually mirror successive eligible L plans.
            (variant / 4) & 1 == 0 ? -structure.width * .31 : structure.width * .31,
            -structure.depth * .12,
            max(structure.width * .38, f32(4.5)),
            max(structure.depth * .76, f32(4.5)),
            .78,
        }
        result.count = 2
    } else if archetype == .Mixed_Use_Dwelling && structure.width >= 22 && structure.depth >= 18 && variant % 6 == 5 {
        // Broad mixed-use parcels can wrap two private rear ranges around a
        // small service court. The full-width street bar still carries the
        // shop and upper apartments, preserving the storefront grammar.
        result.masses[0] = {0, structure.depth * .18, structure.width, structure.depth * .64, 1}
        result.masses[1] = {
            -structure.width * .31,
            -structure.depth * .20,
            max(structure.width * .32, f32(4.5)),
            max(structure.depth * .36, f32(4.5)),
            .68,
        }
        result.masses[2] = {
            structure.width * .31,
            -structure.depth * .20,
            max(structure.width * .32, f32(4.5)),
            max(structure.depth * .36, f32(4.5)),
            .68,
        }
        result.count = 3
    } else if archetype == .Mixed_Use_Dwelling && structure.width >= 14 && structure.depth >= 14 {
        // The full-width street range holds the shop and upper rooms; the
        // lower rear wing reads as the private part of the dwelling. Most
        // variants mirror an L; every third uses a centered T-plan.
        result.masses[0] = {0, structure.depth * .18, structure.width, structure.depth * .64, 1}
        result.masses[1] = {
            variant % 3 == 2 ? f32(0) : (variant & 1) == 0 ? -structure.width * .27 : structure.width * .27,
            -structure.depth * .20,
            variant % 3 == 2 ? max(structure.width * .54, f32(4.5)) : max(structure.width * .46, f32(4.5)),
            max(structure.depth * .42, f32(4.5)),
            variant % 3 == 2 ? f32(.76) : f32(.72),
        }
        result.count = 2
    } else if archetype == .Shop_House && structure.width >= 16 && structure.depth >= 14 && variant % 4 == 0 {
        // Shop houses need more than a townhouse silhouette: keep the public
        // sales room across the street edge and attach a lower rear stockroom
        // with a generous internal connection for goods circulation.
        result.masses[0] = {0, structure.depth * .22, structure.width, structure.depth * .56, 1}
        result.masses[1] = {
            // Eligible seeds are multiples of four; their parity cannot
            // select a side. Advance through those eligible variants instead.
            (variant / 4) & 1 == 0 ? -structure.width * .24 : structure.width * .24,
            -structure.depth * .17,
            structure.width * .48,
            structure.depth * .52,
            .70,
        }
        result.count = 2
    } else if (archetype == .Townhouse || archetype == .Shop_House) &&
       structure.width >= 16 &&
       structure.depth >= 16 &&
       variant % 6 == 1 {
        // Street range plus a narrow rear return. Attached buildings therefore
        // vary in depth as well as using the side-to-side stepped composition.
        result.masses[0] = {0, structure.depth * .18, structure.width, structure.depth * .64, 1}
        result.masses[1] = {
            // % 6 == 1 also fixes parity, so derive mirroring from the
            // sequence number among eligible return-plan seeds.
            (variant / 6) & 1 == 0 ? -structure.width * .30 : structure.width * .30,
            -structure.depth * .25,
            max(structure.width * .40, f32(4.5)),
            max(structure.depth * .50, f32(4.5)),
            .76,
        }
        result.count = 2
    } else if (archetype == .Townhouse || archetype == .Shop_House) &&
       structure.width >= 12 &&
       structure.depth >= 12 &&
       variant % 3 == 2 {
        // Stepped plan: two attached bars with unequal depth and height.
        result.masses[0] = {-structure.width * .22, 0, max(structure.width * .56, f32(4.5)), structure.depth, 1}
        result.masses[1] = {
            structure.width * .10,
            -structure.depth * .10,
            max(structure.width * .44, f32(4.5)),
            max(structure.depth * .80, f32(4.5)),
            .72,
        }
        result.count = 2
    } else if archetype == .Post_Office && structure.width >= 24 && structure.depth >= 18 && variant % 4 == 2 {
        // High-volume post offices add a lower parcel/loading annex beside
        // the centered sorting room. It joins the sorting range rather than
        // the public counter hall, keeping back-of-house circulation legible
        // while breaking the repeated civic T-plan silhouette.
        side := (variant & 4) == 0 ? f32(-1) : f32(1)
        parcel_depth := max(structure.depth * .20, f32(4.5))
        result.masses[0] = {0, structure.depth * .20, structure.width, structure.depth * .60, 1}
        result.masses[1] = {0, -structure.depth * .24, structure.width * .54, structure.depth * .52, .72}
        result.masses[2] = {
            side * structure.width * .325,
            -structure.depth * .5 + parcel_depth * .5,
            max(structure.width * .28, f32(4.5)),
            parcel_depth,
            .58,
        }
        result.count = 3
    } else if archetype == .Post_Office && structure.width >= 16 && structure.depth >= 14 {
        // Keep the public counter and post boxes on the street, with a lower
        // sorting/loading range behind. Centering the work range gives mail a
        // direct path from the public hall to the rear service yard.
        result.masses[0] = {0, structure.depth * .20, structure.width, structure.depth * .60, 1}
        result.masses[1] = {0, -structure.depth * .22, structure.width * .56, structure.depth * .56, .72}
        result.count = 2
    } else if archetype == .Clinic && structure.width >= 24 && structure.depth >= 18 && variant % 4 == 2 {
        // A broad clinic can wrap paired recovery wards around a sheltered
        // healing garden. The full-width public waiting/treatment hall stays
        // on the street, while both quieter wings retain deep internal joins
        // and direct rear-yard access.
        result.masses[0] = {0, structure.depth * .22, structure.width, structure.depth * .56, 1}
        result.masses[1] = {
            -structure.width * .35,
            -structure.depth * .18,
            max(structure.width * .30, f32(4.5)),
            max(structure.depth * .52, f32(4.5)),
            .78,
        }
        result.masses[2] = {
            structure.width * .35,
            -structure.depth * .18,
            max(structure.width * .30, f32(4.5)),
            max(structure.depth * .52, f32(4.5)),
            .78,
        }
        result.count = 3
    } else if archetype == .Clinic && structure.width >= 16 && structure.depth >= 14 {
        // Clinics gain a quieter examination/ward return behind the public
        // waiting-room bar. Mirror it by seed so repeated clinics do not all
        // expose the same side wall to their neighboring parcel.
        side := (variant & 1) == 0 ? f32(-1) : f32(1)
        result.masses[0] = {0, structure.depth * .20, structure.width, structure.depth * .60, 1}
        result.masses[1] = {
            side * structure.width * .25,
            -structure.depth * .20,
            structure.width * .50,
            structure.depth * .60,
            .78,
        }
        result.count = 2
    } else if archetype == .Storehouse && structure.width >= 20 && structure.depth >= 16 && variant % 8 == 0 {
        // Storehouses keep a broad street-facing warehouse with an offset,
        // lower loading/packing annex behind it. The shallow rear bar leaves
        // yard space while its deep overlap supports cart-width circulation.
        result.masses[0] = {0, structure.depth * .16, structure.width, structure.depth * .68, 1}
        result.masses[1] = {
            // Multiples of eight are all even; use their ordinal so loading
            // annexes genuinely alternate sides across generated lots.
            (variant / 8) & 1 == 0 ? -structure.width * .22 : structure.width * .22,
            -structure.depth * .25,
            structure.width * .56,
            structure.depth * .42,
            .64,
        }
        result.count = 2
    } else if archetype == .Fishery && structure.width >= 18 && structure.depth >= 14 && variant % 4 == 0 {
        // A waterfront processing hall keeps a broad working frontage while a
        // lower centered rear range reads as smokehouse, cold room, and gear
        // store. Their deep T junction supports a real internal work passage.
        result.masses[0] = {0, structure.depth * .18, structure.width, structure.depth * .64, 1}
        result.masses[1] = {0, -structure.depth * .22, structure.width * .40, structure.depth * .56, .62}
        result.count = 2
    } else if (archetype == .Workshop || archetype == .Storehouse || archetype == .Fishery) &&
       structure.width >= 20 &&
       structure.depth >= 16 &&
       variant % 6 == 4 {
        // A working court edged by two unequal sheds gives larger productive
        // sites a broken, three-part roofline instead of another residential L.
        // Keep orientation independent of both the % 6 court selector and
        // the earlier fishery/storehouse special-plan selectors. Low-bit or
        // ordinal choices collapse to one side for at least one archetype.
        court_side := variant & 16 == 0 ? f32(-1) : f32(1)
        result.masses[0] = {0, -structure.depth * .22, structure.width, structure.depth * .48, 1}
        result.masses[1] = {
            court_side * structure.width * .35,
            structure.depth * .13,
            max(structure.width * .30, f32(4.5)),
            max(structure.depth * .48, f32(4.5)),
            .70,
        }
        result.masses[2] = {
            -court_side * structure.width * .36,
            structure.depth * .06,
            max(structure.width * .28, f32(4.5)),
            max(structure.depth * .34, f32(4.5)),
            .58,
        }
        result.count = 3
    } else if (archetype == .Workshop || archetype == .Storehouse || archetype == .Fishery) &&
       structure.width >= 12 &&
       structure.depth >= 12 &&
       variant % 3 != 0 {
        // Productive buildings use a broad working hall and a lower service
        // wing rather than inheriting residential compound proportions.
        result.masses[0] = {0, -structure.depth * .10, structure.width, structure.depth * .76, 1}
        result.masses[1] = {
            (variant & 1) == 0 ? -structure.width * .30 : structure.width * .30,
            structure.depth * .28,
            max(structure.width * .40, f32(4.5)),
            max(structure.depth * .42, f32(4.5)),
            .68,
        }
        result.count = 2
    } else if archetype == .Barn_Granary && structure.width >= 11 && structure.depth >= 10 {
        // Mediterranean agricultural stores are compact masonry ranges. The
        // Adriatic uses a low attached work cell; the Aegean steps a smaller
        // flat-roof stable down the contour. Both keep a broad internal join
        // without inheriting the former full-height hay hall and side aisle.
        side := (variant & 1) == 0 ? f32(-1) : f32(1)
        if identity.region == .Aegean {
            result.masses[0] = {0, structure.depth * .12, structure.width, structure.depth * .76, 1}
            if structure.width >= 14 && structure.depth >= 12 {
                result.masses[1] = {
                    side * structure.width * .24,
                    -structure.depth * .24,
                    max(structure.width * .52, f32(4.5)),
                    max(structure.depth * .40, f32(4.5)),
                    .62,
                }
                result.count = 2
            }
        } else if structure.width >= 14 && structure.depth >= 12 && variant % 3 != 2 {
            result.masses[0] = {0, structure.depth * .10, structure.width, structure.depth * .72, 1}
            result.masses[1] = {
                side * structure.width * .25,
                -structure.depth * .23,
                max(structure.width * .50, f32(4.5)),
                max(structure.depth * .42, f32(4.5)),
                .64,
            }
            result.count = 2
        }
    } else if archetype == .Mill && structure.width >= 9 && structure.depth >= 9 && structure.height >= 5.6 {
        // The 1.28-height inner stage needs enough exposure above the base
        // hall for a sill, a useful vent, and head clearance. Very low mills
        // remain single working halls instead of carrying a sealed roof nub.
        result.masses[0] = {0, 0, structure.width * .78, structure.depth * .78, 1}
        result.masses[1] = {0, 0, max(structure.width * .42, f32(4.5)), max(structure.depth * .42, f32(4.5)), 1.28}
        result.count = 2
    } else if archetype == .Palace_Loggia && structure.width >= 22 && structure.depth >= 18 && variant % 4 == 0 {
        // A palace wraps a rear ceremonial court behind its full-width public
        // street range. The paired wings overlap that range deeply enough for
        // real circulation.
        result.masses[0] = {0, structure.depth * .22, structure.width, structure.depth * .56, 1}
        result.masses[1] = {
            -structure.width * .34,
            -structure.depth * .18,
            structure.width * .32,
            structure.depth * .52,
            .78,
        }
        result.masses[2] = {
            structure.width * .34,
            -structure.depth * .18,
            structure.width * .32,
            structure.depth * .52,
            .78,
        }
        result.count = 3
    } else if archetype == .Monastery && structure.width >= 22 && structure.depth >= 18 && variant % 4 == 0 {
        // A monastery uses the inverse C-plan: a full-width communal range at
        // the rear and paired cell ranges reaching the street around a quiet,
        // front-open cloister court. This no longer duplicates the palace plan.
        result.masses[0] = {0, -structure.depth * .32, structure.width, structure.depth * .36, 1}
        result.masses[1] = {
            -structure.width * .34,
            structure.depth * .08,
            structure.width * .32,
            structure.depth * .84,
            .78,
        }
        result.masses[2] = {
            structure.width * .34,
            structure.depth * .08,
            structure.width * .32,
            structure.depth * .84,
            .78,
        }
        result.count = 3
    } else if archetype == .Market_Hall && structure.width >= 22 && structure.depth >= 18 && variant % 4 == 2 {
        // A basilica market variant pairs a tall, full-depth trading nave
        // with lower permanent-stall aisles. The ten-percent-width joins
        // keep both aisles connected while leaving the nave wall exposed
        // above their roofs for a useful clerestory band.
        result.masses[0] = {0, 0, structure.width * .56, structure.depth, 1}
        result.masses[1] = {
            -structure.width * .34,
            -structure.depth * .06,
            structure.width * .32,
            structure.depth * .88,
            .68,
        }
        result.masses[2] = {
            structure.width * .34,
            -structure.depth * .06,
            structure.width * .32,
            structure.depth * .88,
            .68,
        }
        result.count = 3
    } else if archetype == .Market_Hall && structure.width >= 22 && structure.depth >= 18 {
        // A broad market gets a centered rear trading hall, producing a T-plan
        // with a full-width public frontage instead of a domestic-looking L.
        result.masses[0] = {0, structure.depth * .20, structure.width, structure.depth * .60, 1}
        result.masses[1] = {0, -structure.depth * .20, structure.width * .56, structure.depth * .60, .82}
        result.count = 2
    } else if archetype == .Harbor_Office && structure.width >= 22 && structure.depth >= 18 {
        // Large quay offices combine a public street counter with a taller
        // dispatch wing and a low records/gear range around an asymmetric
        // working yard. Both rear ranges overlap the street bar deeply enough
        // for real circulation while leaving the yard visibly open.
        side := (variant & 1) == 0 ? f32(-1) : f32(1)
        result.masses[0] = {0, structure.depth * .22, structure.width, structure.depth * .56, 1}
        result.masses[1] = {
            side * structure.width * .31,
            -structure.depth * .18,
            structure.width * .38,
            structure.depth * .52,
            .82,
        }
        result.masses[2] = {
            -side * structure.width * .37,
            -structure.depth * .16,
            structure.width * .26,
            structure.depth * .44,
            .58,
        }
        result.count = 3
    } else if archetype == .Palace_Loggia ||
       archetype == .Market_Hall ||
       archetype == .Harbor_Office ||
       archetype == .Monastery {
        result.masses[0] = {0, structure.depth * .18, structure.width, structure.depth * .64, 1}
        if structure.width >= 12 && structure.depth >= 12 {
            result.masses[1] = {
                (variant & 1) == 0 ? -structure.width * .30 : structure.width * .30,
                -structure.depth * .20,
                max(structure.width * .40, f32(4.5)),
                max(structure.depth * .56, f32(4.5)),
                .78,
            }
            result.count = 2
        }
    } else if archetype == .Campanile {
        // A campanile is a freestanding vertical landmark, not a full-parcel
        // hall with a small crown. Keep its square shaft centered within the
        // authored lot and cap extreme broad-lot growth at eight metres.
        short_side := min(structure.width, structure.depth)
        if short_side >= ARCHITECTURE_MIN_OPENING_FACE_SPAN {
            minimum_span := min(short_side, f32(4.5))
            maximum_span := min(short_side, f32(8))
            tower_span := clamp(short_side * .62, minimum_span, maximum_span)
            result.masses[0] = {0, 0, tower_span, tower_span, 1}
        }
    } else if archetype == .Church &&
       structure.width >= 9 &&
       structure.depth >= 12 &&
       structure.height >= ARCHITECTURE_MIN_OPENING_WALL_HEIGHT / .72 {
        // Build an actual Latin-cross plan instead of laying a shallow wide
        // roof bar over a full-depth rectangle. The nave reaches the street,
        // the transept connects both arms behind its midpoint, and a lower
        // chancel closes the rear of the lot. Size the chancel against the
        // transept's rear edge as well as the lot so every compound church
        // retains a two-metre internal passage rather than merely touching.
        // Delay the cross plan until its lowest transept walls can actually
        // carry openings.
        result.masses[0] = {0, structure.depth * .15, max(structure.width * .60, f32(4.5)), structure.depth * .70, 1}
        result.masses[1] = {0, -structure.depth * .10, structure.width, structure.depth * .42, .72}
        chancel_depth := max(max(structure.depth * .32, f32(4.8)), structure.depth * .19 + 2.05)
        result.masses[2] = {
            0,
            -structure.depth * .5 + chancel_depth * .5,
            max(structure.width * .48, f32(4.5)),
            chancel_depth,
            .86,
        }
        result.count = 3
    } else if archetype == .Fortress_Gate &&
       structure.width >= 12 &&
       structure.depth >= 12 &&
       structure.height >= ARCHITECTURE_MIN_OPENING_WALL_HEIGHT / .68 {
        // Two freestanding towers read as props, not a usable gate complex.
        // A lower full-width guard range joins them across the rear, leaving
        // the central street approach open as a shallow protected court. Do
        // not author the compound until that .68-height guard range can carry
        // its court door; low fortified buildings remain one usable range.
        tower_z := structure.depth * .075
        tower_depth := structure.depth * .85
        tower_width := max(structure.width * .375, f32(4.5))
        tower_x := structure.width * .5 - tower_width * .5
        result.masses[0] = {-tower_x, tower_z, tower_width, tower_depth, 1}
        result.masses[1] = {tower_x, tower_z, tower_width, tower_depth, 1}
        guard_depth := max(structure.depth * .30, f32(4.5))
        result.masses[2] = {0, -structure.depth * .5 + guard_depth * .5, structure.width, guard_depth, .68}
        result.count = 3
    } else if archetype == .Cycladic_Bell && structure.width >= 8 {
        // A Cycladic bell landmark is a compact belfry, not a parcel-depth
        // hall beneath a tower crown. Constrain both axes while retaining a
        // slightly broader whitewashed front wall.
        bell_width := clamp(structure.width * .70, f32(4.5), min(structure.width, f32(8.0)))
        minimum_depth := min(structure.depth, f32(4.5))
        maximum_depth := min(structure.depth, f32(6.5))
        bell_depth := clamp(structure.depth * .48, minimum_depth, maximum_depth)
        result.masses[0] = {0, 0, bell_width, bell_depth, 1}
    }
    if result.count > 1 {
        for mass in result.masses[:result.count] {
            if structure.height * mass.height_scale >= ARCHITECTURE_MIN_OPENING_WALL_HEIGHT do continue
            // Compound ranges represent usable rooms, not roof decoration.
            // If even one authored attachment is too low for the shared door,
            // window, and vent grammar, retain the original full-lot range
            // until the building is tall enough to support the whole plan.
            result.masses[0] = {0, 0, structure.width, structure.depth, 1}
            result.count = 1
            break
        }
    }
    return result
}

@(no_instrumentation)
architecture_frontage_mass_index :: #force_inline proc(structure: terrain.Structure) -> int {
    footprint := architecture_footprint(structure)
    if footprint.count <= 1 do return 0
    identity := architecture_resolve_legacy_identity(structure)
    if identity.archetype == .Monastery &&
       footprint.count == 3 &&
       footprint.masses[0].local_z < footprint.masses[1].local_z {
        // The open cloister court is the monastery's approach. Keep its main
        // door on the communal range facing into that court instead of placing
        // it arbitrarily on one of the symmetric street-reaching cell wings.
        return 0
    }
    if identity.archetype == .Fortress_Gate && footprint.count == 3 {
        // The two towers project farthest, but neither owns a doorway. The
        // full-width rear guard range closes the central court and carries its
        // actual entrance, so paths and façade consumers must target it.
        return 2
    }
    if (identity.archetype == .Workshop || identity.archetype == .Storehouse || identity.archetype == .Fishery) &&
       footprint.count >= 2 {
        // Productive compounds are organized by their broad working hall.
        // A projecting low service wing (or either shed defining a working
        // court) must not steal the entrance and façade attachments merely
        // because its roof edge reaches slightly farther toward the street.
        return 0
    }
    best_index := 0
    best_front := f32(-1.0e20)
    for mass, mass_index in footprint.masses[:footprint.count] {
        // Architecture façades are rendered on +local-Z. Choose the mass
        // whose front plane reaches farthest in that direction so attached
        // details remain visible instead of landing behind a projecting wing.
        front := mass.local_z + mass.depth * .5
        if front > best_front {
            best_front = front
            best_index = mass_index
        }
    }
    return best_index
}
