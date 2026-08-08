package main

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import hero "../packages/hero_buildings"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

settlement_town_district_building_target :: proc(district: Settlement_Neighborhood) -> int {
    target := 1
    if district.age < .78 do target = 2
    if district.density > .24 && district.age < .62 do target = 3
    if district.density > .38 && district.age < .40 do target = 4
    return target
}

settlement_hero_config_for_scale :: proc(kind: hero.Kind, scale: Settlement_Scale) -> hero.Config {
    config := hero.defaults(kind)
    if scale == .Town {
        // Keep civic anchors legible without letting two city-sized compounds
        // consume the silhouette of a compact Riviera town. These remain
        // comfortably above the hero generator's valid minimum dimensions.
        config.frontage = max(config.frontage * .84, f32(18))
        config.depth = max(config.depth * .87, f32(12))
        config.arcade_depth = min(config.arcade_depth, config.depth * .54)
    }
    return config
}

settlement_town_frontage_side_sign :: proc(district_center, route_origin, route_normal: [2]f32, hash: u32) -> f32 {
    side_distance := linalg.dot(district_center - route_origin, route_normal)
    if math.abs(side_distance) > .75 do return side_distance < 0 ? f32(-1) : f32(1)
    return hash & 1 == 0 ? f32(-1) : f32(1)
}

settlement_town_try_pair_singleton :: proc(
    settlement: ^Settlement_Plan,
    project: ^terrain.Project,
    city: ^architecture.City_Plan,
    structure_index: int,
    district: Settlement_Neighborhood,
) -> bool {
    if settlement == nil || project == nil || city == nil || structure_index < 0 || structure_index >= city.count {
        return false
    }
    first := city.structures[structure_index]
    if settlement_structure_is_landmark(first) || buildings.is_landmark(first.building) do return false
    minimum_height, maximum_height := settlement_height_band(settlement.request.region, .Town)
    if first.height > maximum_height + .01 do return false
    // Rescue the missing address with a genuinely narrow infill house. The
    // former near-copy (.82 x .92) usually failed in exactly the constrained
    // frontage gaps this pass exists to repair, leaving a detached singleton
    // surrounded by lawn. Riviera terraces comfortably step down to a four-
    // metre facade and a shallower rear wall while retaining the street line.
    frontage := clamp(first.width * .68, f32(4), f32(7))
    depth := clamp(first.depth * .78, f32(8), f32(16))
    frontage, depth = settlement_normalize_ordinary_building_dimensions(frontage, depth)
    separation := settlement_building_separation(settlement.request.region, .Town, district.age, true)
    tangent := [2]f32{f32(math.cos(f64(first.rotation))), f32(math.sin(f64(first.rotation)))}
    pitch := (first.width + frontage) * .5 + separation + .2
    preferred_side :=
        linalg.dot(district.center - [2]f32{first.center_x, first.center_z}, tangent) < 0 ? f32(-1) : f32(1)
    sides := [2]f32{preferred_side, -preferred_side}
    for side in sides {
        point := [2]f32{first.center_x, first.center_z} + tangent * pitch * side
        if settlement_nearest_committed_road_distance(project, point) > 34 ||
           !settlement_structure_footprint_on_land(project, point[0], point[1], frontage, depth, first.rotation) {
            continue
        }
        rescue_height := architecture.facade_fitted_height_in_range(
            clamp(first.height, minimum_height, maximum_height),
            minimum_height,
            maximum_height,
        )
        candidate := terrain.structure_make(point[0], point[1], frontage, depth, 0, rescue_height)
        candidate.width = frontage
        candidate.depth = depth
        candidate.height = rescue_height
        candidate.rotation = first.rotation
        if !settlement_structure_routes_clear(settlement, candidate) ||
           !settlement_structure_committed_roads_clear(project, candidate) ||
           !settlement_structure_plazas_clear(settlement, candidate) ||
           !settlement_structure_clear(
                   project,
                   city,
                   point[0],
                   point[1],
                   frontage,
                   depth,
                   first.rotation,
                   separation,
               ) {
            continue
        }
        // A rescued terrace mate should share the established facade/roof
        // grammar. A fresh procedural seed can promote the smaller neighbor
        // into an unrelated tall variant during architecture commit.
        seed := first.seed
        candidate.kind = .Architecture
        candidate.seed = seed
        candidate.color = architecture.architecture_color(seed, false)
        if settlement.request.region == .Aegean do candidate.color = {236, 232, 216, 255}
        candidate.building = first.building
        parcel := architecture.City_Parcel {
            frontage_width = frontage,
            depth          = depth,
            density        = clamp(district.density, 0, 1),
            seed           = seed,
            attached       = true,
        }
        half_frontage, half_depth := frontage * .5, depth * .5
        normal := [2]f32{-tangent[1], tangent[0]}
        parcel.corners = {
            point - tangent * half_frontage - normal * half_depth,
            point + tangent * half_frontage - normal * half_depth,
            point + tangent * half_frontage + normal * half_depth,
            point - tangent * half_frontage + normal * half_depth,
        }
        append(&city.structures, candidate)
        append(&city.parcels, parcel)
        city.count += 1
        city.parcel_count += 1
        if settlement.ordinary_purpose_count < len(settlement.ordinary_purposes) {
            settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Dwelling
            switch candidate.building.purpose {
            case .Farmstead:
                settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Farmstead
            case .Barn_Granary:
                settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Barn_Granary
            case .Workshop:
                settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Workshop
            case .Inn_Shop:
                settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Inn_Shop
            case .Mill:
                settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Mill
            case .Fishery:
                settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Fishery
            case .Storehouse:
                settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Storehouse
            case .Dwelling:
            }
            settlement.ordinary_purpose_count += 1
        }
        return true
    }
    return false
}

settlement_plan_generate_buildings :: proc(
    settlement: ^Settlement_Plan,
    project: ^terrain.Project,
    rng: ^Settlement_Rng,
) -> architecture.City_Plan {
    result: architecture.City_Plan
    if settlement == nil || project == nil do return result
    if settlement.request.scale == .Village {
        return settlement_plan_generate_village_buildings(settlement, project, rng)
    }
    hero_post_office_placed := false
    hero_clinic_placed := false
    minimum_height, maximum_height := settlement_height_band(settlement.request.region, settlement.request.scale)
    fabric := settlement.macro_cells[:settlement.macro_cell_count]
    if settlement.request.scale == .Village && settlement.neighborhood_count > 0 {
        // Macro cells remain the density/suitability field, but a village is
        // composed at neighborhood scale. Treating every occupied raster cell
        // as a parcel anchor produces a conspicuous one-building-wide string.
        fabric = settlement.neighborhoods[:settlement.neighborhood_count]
    }
    for district, district_index in fabric {
        hash := u32(district_index) * u32(0x9e3779b9) ~ settlement.request.seed
        if !settlement_fabric_cell_kept(settlement.request.scale, district.age, hash) do continue
        target := 1
        if district.density > .48 && district.age < .78 do target = 2
        if settlement.request.scale == .Town {
            // A single oversized object per macro cell produces suburban
            // dots and can never register a built block. Mature town tissue
            // instead gets short runs of narrow houses sharing one frontage.
            target = settlement_town_district_building_target(district)
        }
        if settlement.request.scale == .City && district.density > .70 && district.age < .52 && hash & 3 != 0 {
            target = 3
        }
        if settlement.request.scale == .Village {
            // One reachable neighborhood must be sufficient to form a real
            // village; additional neighborhoods become satellite compounds,
            // not a prerequisite for meeting the minimum settlement size.
            target = 12 + int(clamp(district.density, 0, 1) * 4)
            if district.age > .72 do target = max(target - 2, 12)
        }
        district_start := result.count
        route_origin, route_tangent, route_normal, route_width, route_shoulder, route_distance, _, route_found :=
            settlement_nearest_route_frame(settlement, district.center)
        if !settlement_fabric_route_reachable(settlement.request.scale, route_distance, route_found) {
            continue
        }
        for slot in 0 ..< target * 5 {
            if result.count - district_start >= target do break
            placement_index := result.count - district_start
            layout_index := slot
            if settlement.request.scale == .Village {
                // Retry a compact slot with several footprint samples, then
                // move past a park, landmark, or unsuitable patch instead of
                // starving the rest of the court. The upper bound prevents
                // rejected candidates from recreating a long raster ribbon.
                attempted_slot := min((slot + 2) / 3, target + 2)
                layout_index = max(placement_index, attempted_slot)
            }
            median_frontage, frontage_low, frontage_high := f32(8.5), f32(4.5), f32(16)
            depth_low, depth_high := f32(9), f32(28)
            if settlement.request.region == .Aegean {
                median_frontage, frontage_low, frontage_high = 6.5, 4, 11
                depth_low, depth_high = 5.5, 16
            } else if settlement.request.scale == .Town {
                // Adriatic town fabric is made from narrow hillside addresses,
                // not the broad apartment and palazzo parcels used by City.
                // The old city limits produced 350–400 m² ordinary slabs that
                // visually crowded roads even when their collision clearance
                // was valid.
                median_frontage, frontage_low, frontage_high = 7, 4.2, 12.5
                depth_low, depth_high = 8, 20
            } else if settlement.request.scale == .Village {
                median_frontage, frontage_low, frontage_high = 7.5, 4.5, 13
                depth_low, depth_high = 6, 18
            }
            frontage := settlement_sample_lognormal(rng, median_frontage, .24, frontage_low, frontage_high)
            ratio_mode, ratio_high := f32(1.65), f32(2.5)
            if settlement.request.region == .Aegean {
                ratio_mode, ratio_high = 1.25, 1.55
            } else if settlement.request.scale == .Town {
                ratio_mode, ratio_high = 1.5, 2.1
            } else if settlement.request.scale == .Village {
                ratio_mode, ratio_high = 1.35, 1.60
            }
            depth := clamp(
                frontage * settlement_sample_triangular(rng, 1.25, ratio_mode, ratio_high),
                depth_low,
                depth_high,
            )
            // Architecture doors and their access paths use the frontage
            // face. Cities and villages present the broad elevation, while
            // Riviera towns retain narrow-fronted, deep row-house parcels so
            // several addresses can compose a continuous street wall.
            if depth > frontage && settlement.request.scale != .Town {
                frontage, depth = depth, frontage
            }
            frontage, depth = settlement_normalize_ordinary_building_dimensions(frontage, depth)
            hero_candidate := !hero_post_office_placed || !hero_clinic_placed
            hero_kind := !hero_post_office_placed ? hero.Kind.Post_Office : hero.Kind.Clinic
            if hero_candidate {
                // Civic buildings are program inputs, not identities painted
                // onto whatever ordinary parcel happens to be large enough.
                // Give placement, collision, terrain, and access planning the
                // purpose-built footprint from the outset.
                hero_config := settlement_hero_config_for_scale(hero_kind, settlement.request.scale)
                frontage = hero_config.frontage
                depth = hero_config.depth
            }
            x, z, rotation: f32
            attached :=
                settlement_rng_unit(rng) < settlement_attachment_probability(district.age, settlement.request.scale)
            separation := settlement_building_separation(
                settlement.request.region,
                settlement.request.scale,
                district.age,
                attached,
            )
            frontage_reach :=
                settlement.request.scale == .City ? f32(30) : settlement.request.scale == .Town ? f32(32) : f32(18)
            if settlement.request.region == .Adriatic {
                frontage_reach =
                    settlement.request.scale == .City ? f32(24) : settlement.request.scale == .Town ? f32(32) : f32(16)
            }
            frontage_slots := settlement.request.scale == .Village ? 1 : 4
            use_frontage := route_found && layout_index < frontage_slots && route_distance <= frontage_reach
            if settlement.request.scale == .Village {
                // A village compound is organized around its court. The
                // pedestrian-access pass connects that court to the nearest
                // road; reserving a special frontage parcel here creates a
                // ribbon/court transition that repeatedly collides.
                use_frontage = false
            }
            if use_frontage {
                // Keep a macro cell's houses on one side of its street and
                // compose them as a short terrace run. Alternating every slot
                // across the carriageway produced isolated zig-zag houses,
                // made a two-house group span an entire block, and forced
                // separate spoke paths to each threshold.
                centered_slot := f32(layout_index) - f32(target - 1) * .5
                signed_row := centered_slot * (frontage + separation)
                // The projected macro-cell centers otherwise line up at
                // identical stations on long routes. Drift each frontage
                // group within its own cell, without changing which street it
                // addresses.
                station_noise := f32((hash ~ u32(0x27d4eb2d)) & 0xffff) / f32(0xffff) - .5
                signed_row += station_noise * district.radius * .25
                // Once an ordinary frontage run has started, place the next
                // successful house from the previous house's actual edge.
                // Deriving every station independently from its own random
                // width leaves conspicuous lawn slots between otherwise
                // attached rowhouses. Keep collision retries free to seek a
                // new station, and keep purpose-built civic parcels detached.
                if layout_index == placement_index && placement_index > 0 && !hero_candidate {
                    previous := result.structures[result.count - 1]
                    if !settlement_structure_is_landmark(previous) {
                        previous_station :=
                            (previous.center_x - route_origin[0]) * route_tangent[0] +
                            (previous.center_z - route_origin[1]) * route_tangent[1]
                        signed_row = previous_station + previous.width * .5 + frontage * .5 + separation
                    }
                }
                side_sign := hash & 1 == 0 ? f32(-1) : f32(1)
                if settlement.request.scale == .Town {
                    // Keep a cell's terrace on the side of the street where
                    // its growth tissue actually lives. Randomly reflecting
                    // whole groups across the route leaves alternating empty
                    // wedges and makes neighboring infill collide.
                    side_sign = settlement_town_frontage_side_sign(district.center, route_origin, route_normal, hash)
                }
                setback_noise := f32((hash >> 12) & 255) / 255
                setback_variation := (.15 + district.age * .65) * setback_noise
                setback := route_width * .5 + route_shoulder + .8 + depth * .5 + separation * .5 + setback_variation
                x = route_origin[0] + route_tangent[0] * signed_row + route_normal[0] * setback * side_sign
                z = route_origin[1] + route_tangent[1] * signed_row + route_normal[1] * setback * side_sign
                rotation = architecture.architecture_frontage_rotation(route_tangent[0], route_tangent[1], side_sign)
            } else {
                // Distant Adriatic districts form compact courts; Aegean and
                // hillside tissue forms contour-aligned attached terraces.
                columns := min(settlement.request.region == .Aegean ? 4 : 3, target)
                row := layout_index / columns
                sample := f32(7)
                gradient_x :=
                    terrain.sample_surface_height(project, 0, district.center[0] + sample, district.center[1]) -
                    terrain.sample_surface_height(project, 0, district.center[0] - sample, district.center[1])
                gradient_z :=
                    terrain.sample_surface_height(project, 0, district.center[0], district.center[1] + sample) -
                    terrain.sample_surface_height(project, 0, district.center[0], district.center[1] - sample)
                gradient_length := linalg.length([2]f32{gradient_x, gradient_z})
                tangent := [2]f32{1, 0}
                if route_found && (settlement.request.region == .Adriatic || settlement.request.scale == .Village) {
                    tangent = route_tangent
                } else if gradient_length > .001 {
                    tangent = {-gradient_z / gradient_length, gradient_x / gradient_length}
                }
                normal := [2]f32{-tangent.y, tangent.x}
                row_count := max((target + columns - 1) / columns, 1)
                centered_row := f32(row) - f32(row_count - 1) * .5
                centered_column := f32(layout_index % columns) - f32(columns - 1) * .5
                column_pitch, row_pitch := frontage + separation, depth + separation
                if settlement.request.scale == .Village {
                    // Stable pitches are based on the largest village parcel,
                    // not the current random sample. Recomputing the grid from
                    // every candidate makes later rows collide with earlier
                    // buildings of a different size.
                    column_pitch, row_pitch = 22, 26
                }
                group_center := district.center
                if settlement.request.scale == .Village && route_found {
                    side_dot :=
                        (district.center[0] - route_origin[0]) * route_normal[0] +
                        (district.center[1] - route_origin[1]) * route_normal[1]
                    side_sign := side_dot < 0 ? f32(-1) : f32(1)
                    if math.abs(side_dot) < .01 && hash & 1 == 0 do side_sign = -1
                    court_half_depth := f32(row_count - 1) * row_pitch * .5 + 9
                    court_offset := route_width * .5 + route_shoulder + 4 + court_half_depth
                    first_center := [2]f32 {
                        route_origin[0] + route_normal[0] * court_offset * side_sign,
                        route_origin[1] + route_normal[1] * court_offset * side_sign,
                    }
                    opposite_center := [2]f32 {
                        route_origin[0] - route_normal[0] * court_offset * side_sign,
                        route_origin[1] - route_normal[1] * court_offset * side_sign,
                    }
                    first_height := terrain.sample_surface_height(project, 0, first_center[0], first_center[1])
                    opposite_height := terrain.sample_surface_height(
                        project,
                        0,
                        opposite_center[0],
                        opposite_center[1],
                    )
                    if first_height <= project.sea_level + .6 || opposite_height > first_height + 1 {
                        side_sign = -side_sign
                    }
                    group_center = {
                        route_origin[0] + route_normal[0] * court_offset * side_sign,
                        route_origin[1] + route_normal[1] * court_offset * side_sign,
                    }
                }
                x =
                    group_center[0] +
                    tangent[0] * centered_column * column_pitch +
                    normal[0] * centered_row * row_pitch
                z =
                    group_center[1] +
                    tangent[1] * centered_column * column_pitch +
                    normal[1] * centered_row * row_pitch
                group_jitter_radius := district.radius
                if settlement.request.scale == .Village {
                    group_jitter_radius = min(group_jitter_radius, 22)
                }
                jitter_tangent := (f32((hash >> 8) & 255) / 255 - .5) * group_jitter_radius * .62
                jitter_normal := (f32((hash >> 16) & 255) / 255 - .5) * group_jitter_radius * .62
                slot_hash := hash ~ u32(slot + 1) * u32(0x165667b1)
                jitter_tangent += (f32(slot_hash & 255) / 255 - .5) * min(district.radius * .24, frontage * .55)
                jitter_normal += (f32((slot_hash >> 8) & 255) / 255 - .5) * min(district.radius * .18, depth * .35)
                x += tangent[0] * jitter_tangent + normal[0] * jitter_normal
                z += tangent[1] * jitter_tangent + normal[1] * jitter_normal
                rotation = f32(math.atan2(f64(tangent[1]), f64(tangent[0])))
                if settlement.request.region == .Adriatic &&
                   district.tissue != .Later_Extension &&
                   district.tissue != .Dalmatian_Planned {
                    rotation_noise :=
                        (f32((slot_hash >> 16) & 255) / 255 - .5) * (district.age < .7 ? f32(.34) : f32(.14))
                    rotation += rotation_noise
                } else if settlement.request.region == .Aegean {
                    rotation_span := f32(.34)
                    if district.tissue == .Later_Extension {
                        rotation_span = .10
                    } else if settlement.request.scale == .Village {
                        rotation_span = .18
                    }
                    rotation += (f32((slot_hash >> 16) & 255) / 255 - .5) * rotation_span
                }
                rotation = settlement_rotation_face_point(rotation, {x, z}, group_center)
            }
            if settlement.request.scale == .Town && settlement_nearest_committed_road_distance(project, {x, z}) > 34 {
                // Optional planned lanes may be simplified out or declined
                // when the shared road graph reaches its budget. Never place
                // town fabric against such a paper street: the access repair
                // would otherwise draw a conspicuous 60–100 m footpath to the
                // nearest road that actually renders.
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            if !settlement_structure_footprint_on_land(project, x, z, frontage, depth, rotation) {
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            candidate_structure := terrain.structure_make(x, z, frontage, depth, 0, .25)
            candidate_structure.width = frontage
            candidate_structure.depth = depth
            candidate_structure.rotation = rotation
            if !settlement_structure_routes_clear(settlement, candidate_structure) ||
               !settlement_structure_committed_roads_clear(project, candidate_structure) {
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            if !settlement_structure_plazas_clear(settlement, candidate_structure) {
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            if !settlement_structure_clear(project, &result, x, z, frontage, depth, rotation, separation) {
                settlement_plan_record_rejected_site(settlement, x, z, frontage, depth, rotation)
                continue
            }
            seed := settlement_rng_u32(rng)
            hero_plan: hero.Plan
            if hero_candidate {
                hero_config := settlement_hero_config_for_scale(hero_kind, settlement.request.scale)
                hero_config.frontage = frontage
                hero_config.depth = depth
                hero_plan = hero.generate(seed, hero_config)
            }
            density := clamp(district.density, 0, 1)
            height_roll := settlement_rng_unit(rng)
            height_factor := clamp(density * .78 + height_roll * .22, 0, 1)
            if settlement.request.region == .Aegean {
                // Aegean settlements need occasional upper rooms and roof
                // terraces stepping above the predominantly low fabric. The
                // former range could never cross the 7.2 m module threshold
                // at Town density, so every ordinary house became 4.8 m.
                height_factor = clamp(density * .90 + height_roll * .42, 0, 1)
            }
            height := minimum_height + (maximum_height - minimum_height) * height_factor
            height = architecture.facade_fitted_height_in_range(height, minimum_height, maximum_height)
            if hero_candidate do height = hero_plan.arcade_height + hero_plan.roof_height + hero_plan.monitor_height
            structure := terrain.structure_make(x, z, frontage, depth, 0, height)
            structure.kind = .Architecture
            structure.seed = seed
            structure.width = frontage
            structure.depth = depth
            structure.height = height
            structure.rotation = rotation
            identity := architecture.architecture_identity({
                    region           = settlement_building_region(settlement.request.region),
                    tissue           = settlement_architecture_tissue(district.tissue),
                    density          = density,
                    attached         = attached,
                    frontage         = frontage,
                    depth            = depth,
                    route            = route_found ? architecture.Context_Route.Street : architecture.Context_Route.Unspecified,
                    waterfront       = district.tissue == .Harbor,
                    purpose_explicit = false,
                }, seed)
            if hero_candidate {
                landmark_kind := buildings.Landmark_Kind.Post_Office
                if hero_kind == .Clinic do landmark_kind = .Clinic
                identity = architecture.architecture_identity({
                        region        = settlement_building_region(settlement.request.region),
                        landmark_kind = landmark_kind,
                        frontage      = frontage,
                        depth         = depth,
                    }, seed)
                if hero_kind == .Clinic {
                    hero_clinic_placed = true
                } else {
                    hero_post_office_placed = true
                }
            }
            structure.building = identity
            structure.color = architecture.architecture_color(seed, false)
            if settlement.request.region == .Aegean do structure.color = {236, 232, 216, 255}
            parcel := architecture.City_Parcel {
                frontage_width = frontage,
                depth          = depth,
                density        = density,
                seed           = seed,
                attached       = attached,
            }
            half_frontage, half_depth := frontage * .5, depth * .5
            tangent := [2]f32{f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))}
            normal := [2]f32{-tangent[1], tangent[0]}
            parcel.corners = {
                {
                    x - tangent[0] * half_frontage - normal[0] * half_depth,
                    z - tangent[1] * half_frontage - normal[1] * half_depth,
                },
                {
                    x + tangent[0] * half_frontage - normal[0] * half_depth,
                    z + tangent[1] * half_frontage - normal[1] * half_depth,
                },
                {
                    x + tangent[0] * half_frontage + normal[0] * half_depth,
                    z + tangent[1] * half_frontage + normal[1] * half_depth,
                },
                {
                    x - tangent[0] * half_frontage + normal[0] * half_depth,
                    z - tangent[1] * half_frontage + normal[1] * half_depth,
                },
            }
            append(&result.structures, structure)
            if settlement.ordinary_purpose_count < len(settlement.ordinary_purposes) {
                if hero_candidate {
                    settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Inn_Shop
                } else {
                    switch identity.purpose {
                    case .Dwelling:
                        settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Dwelling
                    case .Farmstead:
                        settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Farmstead
                    case .Barn_Granary:
                        settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Barn_Granary
                    case .Workshop:
                        settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Workshop
                    case .Inn_Shop:
                        settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Inn_Shop
                    case .Mill:
                        settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Mill
                    case .Fishery:
                        settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Fishery
                    case .Storehouse:
                        settlement.ordinary_purposes[settlement.ordinary_purpose_count] = .Storehouse
                    }
                }
                settlement.ordinary_purpose_count += 1
            }
            result.count += 1
            append(&result.parcels, parcel)
            result.parcel_count += 1
        }
        if settlement.request.scale == .Town &&
           result.count - district_start == 1 &&
           district.density >= .18 &&
           district.age < .92 {
            _ = settlement_town_try_pair_singleton(settlement, project, &result, district_start, district)
        }
        settlement_plan_record_built_group(
            settlement,
            &result,
            district_start,
            result.count - district_start,
            district.tissue,
        )
    }
    // Buildings establish the construction datum. Lightly settle steep town
    // footprints before routing passages so thresholds, stoops, and the A*
    // grade checks all observe the same finished ground that will be rendered.
    settlement_plan_prepare_block_terrain(settlement, project, &result)
    settlement_plan_seat_city(&result, project)
    settlement_plan_generate_pedestrian_access(settlement, &result, rng)
    maximum_access_length := settlement.request.scale == .City ? f32(180) : f32(150)
    _ = settlement_plan_generate_building_access(settlement, project, &result, rng, maximum_access_length)
    settlement_plan_generate_lamps(settlement, &result)
    return result
}
