package harbor

import boats "../boats"
import terrain "../terrain"
import "core:math"

GENERATION_VERSION :: u16(2)
MIN_DIAMETER_METERS :: f32(150)
MAX_DIAMETER_METERS :: f32(450)
SITE_SAMPLE_CAPACITY :: 65
CONTOUR_CAPACITY :: 96
STRUCTURE_CAPACITY :: 24
STRUCTURE_POINT_CAPACITY :: 12
BERTH_CAPACITY :: 128
ROUTE_CAPACITY :: BERTH_CAPACITY
ROUTE_POINT_CAPACITY :: 16
TERRAIN_EDIT_CAPACITY :: 32
CANDIDATE_COUNT :: 12
SITE_TRIAL_CAPACITY :: 6
COASTAL_SITE_CAPACITY :: 24
HISTORICAL_PHASE_CAPACITY :: 5
WATERFRONT_ZONE_CAPACITY :: 12

Vec2 :: struct {
    x, z: f32,
}

Bounds :: struct {
    minimum, maximum: Vec2,
}

Archetype :: enum u8 {
    Fishing_Cove,
    Quay_Harbor,
    Protected_Town_Marina,
    Island_Harbor,
    Open_Mooring_Harbor,
}

Settlement_Role :: enum u8 {
    Village,
    Town,
    Working_Port,
}

Harbor_Purpose :: enum u8 {
    Fishing,
    Ferry,
    Mixed_Town,
    Leisure,
    Working_Port,
}

Harbor_Strategy :: enum u8 {
    Natural_Anchorage,
    Beach_Landing,
    Shoreline_Quay,
    Single_Hooked_Mole,
    Offset_Twin_Moles,
    Dredged_Basin,
    Excavated_Pocket,
    Reclaimed_Port,
}

Coastal_Opportunity :: enum u8 {
    Open_Coast,
    Lee_Shore,
    Cove,
    Headland,
    River_Mouth,
    Island_Sound,
}

Historical_Phase_Kind :: enum u8 {
    Original_Landing,
    First_Protection,
    Working_Extension,
    Modernization,
    Overflow_Moorings,
}

Waterfront_Use :: enum u8 {
    Landing,
    Fish_Market,
    Repair_Yard,
    Harbor_Office,
    Ferry_Access,
    Working_Apron,
}

Structure_Kind :: enum u8 {
    Quay,
    Breakwater,
    Pier,
    Natural_Jetty,
}

Structure_Material :: enum u8 {
    Timber,
    Stone,
    Rubble,
    Concrete,
}

Berth_Kind :: enum u8 {
    Slip,
    Swing_Mooring,
}

Terrain_Edit_Kind :: enum u8 {
    Dredge,
    Cut,
    Fill,
    Feather,
}

Contour :: struct {
    points: [CONTOUR_CAPACITY]Vec2,
    count:  int,
}

Structure_Path :: struct {
    kind:     Structure_Kind,
    material: Structure_Material,
    width:    f32,
    points:   [STRUCTURE_POINT_CAPACITY]Vec2,
    count:    int,
}

Berth :: struct {
    position:         Vec2,
    yaw:              f32,
    class:            boats.Class,
    kind:             Berth_Kind,
    occupied:         bool,
    clearance_radius: f32,
}

Route :: struct {
    points:      [ROUTE_POINT_CAPACITY]Vec2,
    count:       int,
    berth_index: int,
}

Terrain_Edit :: struct {
    kind:     Terrain_Edit_Kind,
    center:   Vec2,
    radius:   f32,
    target_y: f32,
    feather:  f32,
}

Harbor_Site :: struct {
    valid:             bool,
    anchor:            Vec2,
    tangent:           Vec2,
    outward:           Vec2,
    sea_level:         f32,
    preferred_scale:   f32,
    shoreline:         Contour,
    water_depths:      [SITE_SAMPLE_CAPACITY]f32,
    water_depth_count: int,
    open_water_score:  f32,
    backland_score:    f32,
    exposure_score:    f32,
    curvature_score:   f32,
    slope_score:       f32,
    town_distance:     f32,
    construction_cost: f32,
    selection_score:   f32,
    opportunity:       Coastal_Opportunity,
}

Coastal_Survey :: struct {
    settlement_anchor: Vec2,
    search_radius:     f32,
    sites:             [COASTAL_SITE_CAPACITY]Harbor_Site,
    site_count:        int,
    ring_valid_counts: [3]int,
    minimum_scale:     f32,
    maximum_scale:     f32,
}

Harbor_Program :: struct {
    role:                  Settlement_Role,
    purpose:               Harbor_Purpose,
    population:            int,
    target_capacity:       int,
    minimum_capacity:      int,
    design_vessel_length:  f32,
    shelter_requirement:   f32,
    construction_budget:   f32,
    maximum_town_distance: f32,
    allow_major_works:     bool,
}

Historical_Phase :: struct {
    kind:            Historical_Phase_Kind,
    structure_first: int,
    structure_count: int,
    berth_first:     int,
    berth_count:     int,
    terrain_first:   int,
    terrain_count:   int,
}

Waterfront_Zone :: struct {
    use:      Waterfront_Use,
    center:   Vec2,
    width:    f32,
    depth:    f32,
    landward: Vec2,
}

Harbor_Intervention :: struct {
    seed:                    u32,
    valid:                   bool,
    downgraded:              bool,
    strategy:                Harbor_Strategy,
    program:                 Harbor_Program,
    site:                    Harbor_Site,
    phases:                  [HISTORICAL_PHASE_CAPACITY]Historical_Phase,
    phase_count:             int,
    waterfront_zones:        [WATERFRONT_ZONE_CAPACITY]Waterfront_Zone,
    waterfront_count:        int,
    runtime_plan:            Harbor_Plan,
    construction_cost:       f32,
    achieved_capacity:       int,
    downgrade_steps:         int,
    terrain_edit_area:       f32,
    dredged_area:            f32,
    cut_volume:              f32,
    fill_volume:             f32,
    terrain_area_limit:      f32,
    terrain_volume_limit:    f32,
    terrain_budget_exceeded: bool,
}

Harbor_Diagnostics :: struct {
    valid:                     bool,
    capacity_exceeded:         bool,
    footprint_diameter:        f32,
    minimum_depth:             f32,
    shelter_score:             f32,
    navigation_score:          f32,
    naturalism_score:          f32,
    dominant_orientation:      f32,
    dominant_orientation_part: f32,
    rectangularity:            f32,
    mooring_lattice_matches:   int,
    route_failures:            int,
    clearance_failures:        int,
}

Harbor_Plan :: struct {
    seed:                  u32,
    generation_version:    u16,
    archetype:             Archetype,
    valid:                 bool,
    bounds:                Bounds,
    origin:                Vec2,
    tangent:               Vec2,
    outward:               Vec2,
    sea_level:             f32,
    shoreline:             Contour,
    navigable_water:       Contour,
    fairway:               Contour,
    turning_basin:         Contour,
    structures:            [STRUCTURE_CAPACITY]Structure_Path,
    structure_count:       int,
    berths:                [BERTH_CAPACITY]Berth,
    berth_count:           int,
    routes:                [ROUTE_CAPACITY]Route,
    route_count:           int,
    terrain_edits:         [TERRAIN_EDIT_CAPACITY]Terrain_Edit,
    terrain_edit_count:    int,
    office:                Vec2,
    settlement_connection: Vec2,
    entrance:              Vec2,
    diagnostics:           Harbor_Diagnostics,
}

translate_point :: #force_inline proc(point: ^Vec2, dx, dz: f32) {
    point.x += dx
    point.z += dz
}

translate_contour :: proc(contour: ^Contour, dx, dz: f32) {
    if contour == nil do return
    for &point in contour.points[:contour.count] do translate_point(&point, dx, dz)
}

translate_site :: proc(site: ^Harbor_Site, dx, dz: f32) {
    if site == nil do return
    translate_point(&site.anchor, dx, dz)
    translate_contour(&site.shoreline, dx, dz)
}

translate_plan :: proc(plan: ^Harbor_Plan, dx, dz: f32) {
    if plan == nil do return
    translate_point(&plan.bounds.minimum, dx, dz)
    translate_point(&plan.bounds.maximum, dx, dz)
    translate_point(&plan.origin, dx, dz)
    translate_contour(&plan.shoreline, dx, dz)
    translate_contour(&plan.navigable_water, dx, dz)
    translate_contour(&plan.fairway, dx, dz)
    translate_contour(&plan.turning_basin, dx, dz)
    for &structure in plan.structures[:plan.structure_count] {
        for &point in structure.points[:structure.count] do translate_point(&point, dx, dz)
    }
    for &berth in plan.berths[:plan.berth_count] do translate_point(&berth.position, dx, dz)
    for &route in plan.routes[:plan.route_count] {
        for &point in route.points[:route.count] do translate_point(&point, dx, dz)
    }
    for &edit in plan.terrain_edits[:plan.terrain_edit_count] do translate_point(&edit.center, dx, dz)
    translate_point(&plan.office, dx, dz)
    translate_point(&plan.settlement_connection, dx, dz)
    translate_point(&plan.entrance, dx, dz)
}

translate_intervention :: proc(intervention: ^Harbor_Intervention, dx, dz: f32) {
    if intervention == nil do return
    translate_site(&intervention.site, dx, dz)
    for &zone in intervention.waterfront_zones[:intervention.waterfront_count] {
        translate_point(&zone.center, dx, dz)
        translate_point(&zone.landward, dx, dz)
    }
    translate_plan(&intervention.runtime_plan, dx, dz)
}

length :: #force_inline proc(value: Vec2) -> f32 {
    return f32(math.sqrt(f64(value.x * value.x + value.z * value.z)))
}

normalize :: proc(value: Vec2) -> Vec2 {
    magnitude := length(value)
    if magnitude <= .0001 do return {0, 1}
    return {value.x / magnitude, value.z / magnitude}
}

add :: #force_inline proc(a, b: Vec2) -> Vec2 {
    return {a.x + b.x, a.z + b.z}
}

sub :: #force_inline proc(a, b: Vec2) -> Vec2 {
    return {a.x - b.x, a.z - b.z}
}

scale :: #force_inline proc(value: Vec2, amount: f32) -> Vec2 {
    return {value.x * amount, value.z * amount}
}

dot :: #force_inline proc(a, b: Vec2) -> f32 {
    return a.x * b.x + a.z * b.z
}

distance :: #force_inline proc(a, b: Vec2) -> f32 {
    return length(sub(a, b))
}

mix_seed :: proc(value: u32) -> u32 {
    result := value
    result = (result ~ (result >> 16)) * 0x7feb352d
    result = (result ~ (result >> 15)) * 0x846ca68b
    return result ~ (result >> 16)
}

random_unit :: proc(seed: u32) -> f32 {
    return f32(mix_seed(seed) & 0x00ff_ffff) / f32(0x0100_0000)
}

local_to_world :: proc(origin, tangent, outward, local: Vec2) -> Vec2 {
    return {origin.x + tangent.x * local.x + outward.x * local.z, origin.z + tangent.z * local.x + outward.z * local.z}
}

world_to_local :: proc(origin, tangent, outward, world: Vec2) -> Vec2 {
    delta := sub(world, origin)
    return {dot(delta, tangent), dot(delta, outward)}
}

sample_land_gradient :: proc(project: ^terrain.Project, point: Vec2) -> Vec2 {
    if project == nil do return {}
    water := terrain.sample_water_interface(project, point.x, point.z)
    return normalize({water.shore_normal[0], water.shore_normal[1]})
}

snap_to_shore :: proc(project: ^terrain.Project, anchor: Vec2) -> (Vec2, bool) {
    if project == nil do return anchor, false
    best := anchor
    best_distance := f32(10000)
    for ray in 0 ..< 48 {
        angle := f32(ray) / 48 * math.PI * 2
        direction := Vec2{math.cos(angle), math.sin(angle)}
        previous := anchor
        previous_land := terrain.sample_surface(project, 0, previous.x, previous.z) == .Land
        for step in 1 ..= 100 {
            point := add(anchor, scale(direction, f32(step) * 8))
            land := terrain.sample_surface(project, 0, point.x, point.z) == .Land
            if land != previous_land {
                candidate_distance := distance(anchor, point)
                if candidate_distance < best_distance {
                    best, best_distance = point, candidate_distance
                }
                break
            }
            previous, previous_land = point, land
        }
    }
    return best, best_distance < f32(10000)
}

analyze_coast :: proc(project: ^terrain.Project, anchor: Vec2, preferred_scale: f32) -> Harbor_Site {
    site: Harbor_Site
    if project == nil do return site
    snapped_anchor, snapped := snap_to_shore(project, anchor)
    if !snapped do return site
    site.anchor = snapped_anchor
    site.sea_level = project.sea_level
    site.preferred_scale = clamp(preferred_scale, MIN_DIAMETER_METERS, MAX_DIAMETER_METERS)

    landward := sample_land_gradient(project, snapped_anchor)
    site.outward = scale(landward, -1)
    forward := add(snapped_anchor, scale(site.outward, 24))
    backward := add(snapped_anchor, scale(site.outward, -24))
    if terrain.sample_surface(project, 0, forward.x, forward.z) == .Land &&
       terrain.sample_surface(project, 0, backward.x, backward.z) != .Land {
        site.outward = scale(site.outward, -1)
    }
    site.tangent = {-site.outward.z, site.outward.x}
    half_width := site.preferred_scale * .5
    sample_count := 33
    water_good, backland_good := 0, 0
    for index in 0 ..< sample_count {
        lateral := -half_width + f32(index) / f32(sample_count - 1) * site.preferred_scale
        base := add(snapped_anchor, scale(site.tangent, lateral))
        boundary := base
        found := false
        previous := add(base, scale(site.outward, -96))
        previous_land := terrain.sample_surface(project, 0, previous.x, previous.z) == .Land
        for step in 1 ..= 72 {
            offset := -96 + f32(step) * 4
            point := add(base, scale(site.outward, offset))
            land := terrain.sample_surface(project, 0, point.x, point.z) == .Land
            if previous_land && !land {
                boundary = point
                found = true
                break
            }
            previous, previous_land = point, land
        }
        if !found do continue
        site.shoreline.points[site.shoreline.count] = boundary
        site.shoreline.count += 1
        water_point := add(boundary, scale(site.outward, site.preferred_scale * .32))
        depth := terrain.sample_water_interface(project, water_point.x, water_point.z).depth
        site.water_depths[site.water_depth_count] = depth
        site.water_depth_count += 1
        if depth >= 0 do water_good += 1
        land_point := add(boundary, scale(site.outward, -24))
        land_height, _, land_found := terrain.sample_land(project, 0, land_point.x, land_point.z)
        if land_found && land_height > site.sea_level + .35 {
            backland_good += 1
        }
    }
    if site.water_depth_count > 0 {
        site.open_water_score = f32(water_good) / f32(site.water_depth_count)
        site.backland_score = f32(backland_good) / f32(site.water_depth_count)
    }
    if site.shoreline.count >= 3 {
        first := site.shoreline.points[0]
        middle := site.shoreline.points[site.shoreline.count / 2]
        last := site.shoreline.points[site.shoreline.count - 1]
        chord_middle := scale(add(first, last), .5)
        indentation := -dot(sub(middle, chord_middle), site.outward)
        site.curvature_score = clamp(indentation / max(site.preferred_scale * .2, f32(1)), -1, 1)
        site.opportunity =
            site.curvature_score > .22 ? Coastal_Opportunity.Cove : site.curvature_score > .06 ? Coastal_Opportunity.Lee_Shore : site.curvature_score < -.15 ? Coastal_Opportunity.Headland : Coastal_Opportunity.Open_Coast
    }
    water_origin := add(site.anchor, scale(site.outward, site.preferred_scale * .22))
    exposed_rays := 0
    ray_count := 12
    for ray in 0 ..< ray_count {
        angle := -math.PI * .72 + f32(ray) / f32(ray_count - 1) * math.PI * 1.44
        cosine, sine := math.cos(angle), math.sin(angle)
        direction := add(scale(site.outward, cosine), scale(site.tangent, sine))
        blocked := false
        for step in 1 ..= 12 {
            point := add(water_origin, scale(direction, f32(step) * site.preferred_scale / 12))
            if terrain.sample_surface(project, 0, point.x, point.z) == .Land {
                blocked = true
                break
            }
        }
        if !blocked do exposed_rays += 1
    }
    site.exposure_score = f32(exposed_rays) / f32(ray_count)
    site.slope_score = 1 - site.backland_score
    site.construction_cost = clamp(
        site.exposure_score * .42 +
        site.slope_score * .24 +
        (1 - site.open_water_score) * .22 +
        max(-site.curvature_score, f32(0)) * .12,
        0,
        1,
    )
    site.valid = site.shoreline.count >= 10 && site.open_water_score >= .35 && site.backland_score >= .25
    return site
}

survey_coast :: proc(project: ^terrain.Project, settlement_anchor: Vec2, search_radius: f32) -> Coastal_Survey {
    survey: Coastal_Survey
    if project == nil || search_radius <= 0 do return survey
    survey.settlement_anchor = settlement_anchor
    survey.search_radius = search_radius
    survey.minimum_scale = 10000
    rings := [3]f32{.34, .67, 1}
    scale_factors := [3]f32{.24, .42, .62}
    samples_per_ring := COASTAL_SITE_CAPACITY / len(rings)
    for ring, ring_index in rings {
        // Offset successive rings so radial spokes do not repeatedly snap to
        // the same shoreline arc. Eight samples per ring exactly fill the
        // bounded survey while guaranteeing that the far coast is examined.
        angle_offset := f32(ring_index) * math.PI / f32(samples_per_ring)
        for sample_index in 0 ..< samples_per_ring {
            if survey.site_count >= COASTAL_SITE_CAPACITY do return survey
            angle := angle_offset + f32(sample_index) / f32(samples_per_ring) * math.PI * 2
            approximate := Vec2 {
                settlement_anchor.x + math.cos(angle) * search_radius * ring,
                settlement_anchor.z + math.sin(angle) * search_radius * ring,
            }
            site := analyze_coast(
                project,
                approximate,
                clamp(search_radius * scale_factors[ring_index], MIN_DIAMETER_METERS, MAX_DIAMETER_METERS),
            )
            if !site.valid do continue
            survey.ring_valid_counts[ring_index] += 1
            survey.minimum_scale = min(survey.minimum_scale, site.preferred_scale)
            survey.maximum_scale = max(survey.maximum_scale, site.preferred_scale)
            site.town_distance = distance(settlement_anchor, site.anchor)
            duplicate := false
            for existing in survey.sites[:survey.site_count] {
                if distance(existing.anchor, site.anchor) < 55 &&
                   abs(existing.preferred_scale - site.preferred_scale) < 70 {
                    duplicate = true
                    break
                }
            }
            if duplicate do continue
            survey.sites[survey.site_count] = site
            survey.site_count += 1
        }
    }
    if survey.site_count == 0 do survey.minimum_scale = 0
    return survey
}

derive_harbor_program :: proc(role: Settlement_Role, population: int, seed: u32) -> Harbor_Program {
    program: Harbor_Program
    program.role = role
    program.population = max(population, 1)
    switch role {
    case .Village:
        program.purpose = .Fishing
        program.target_capacity = clamp(population / 18 + 8, 8, 24)
        program.minimum_capacity = 4
        program.design_vessel_length = 8
        program.shelter_requirement = .48
        program.construction_budget = .34
        program.maximum_town_distance = 520
    case .Town:
        program.purpose = (seed & 3) == 0 ? Harbor_Purpose.Ferry : Harbor_Purpose.Mixed_Town
        program.target_capacity = clamp(population / 24 + 22, 22, 72)
        program.minimum_capacity = 12
        program.design_vessel_length = program.purpose == .Ferry ? f32(18) : f32(12)
        program.shelter_requirement = .62
        program.construction_budget = .62
        program.maximum_town_distance = 760
    case .Working_Port:
        program.purpose = .Working_Port
        program.target_capacity = clamp(population / 30 + 30, 30, 96)
        program.minimum_capacity = 18
        program.design_vessel_length = 24
        program.shelter_requirement = .72
        program.construction_budget = .92
        program.maximum_town_distance = 900
        program.allow_major_works = true
    }
    return program
}

select_harbor_site :: proc(
    project: ^terrain.Project,
    survey: ^Coastal_Survey,
    program: ^Harbor_Program,
    seed: u32,
) -> Harbor_Site {
    best: Harbor_Site
    if project == nil || survey == nil || program == nil do return best
    best_score := f32(-1000)
    desired_scale := clamp(
        MIN_DIAMETER_METERS + f32(program.target_capacity) / 96 * (MAX_DIAMETER_METERS - MIN_DIAMETER_METERS),
        MIN_DIAMETER_METERS,
        MAX_DIAMETER_METERS,
    )
    for source, index in survey.sites[:survey.site_count] {
        if source.town_distance > program.maximum_town_distance do continue
        site := source
        shelter := 1 - site.exposure_score
        natural_bonus := max(site.curvature_score, f32(0)) * .28
        distance_cost := site.town_distance / max(program.maximum_town_distance, f32(1))
        budget_overrun := max(site.construction_cost - program.construction_budget, f32(0))
        scale_mismatch := abs(site.preferred_scale - desired_scale) / (MAX_DIAMETER_METERS - MIN_DIAMETER_METERS)
        shelter_efficiency := clamp(shelter / max(site.construction_cost, f32(.12)), 0, 2) * .5
        jitter := random_unit(seed ~ u32(index) * 0x9e37_79b9) * .025
        site.selection_score =
            shelter * .22 +
            shelter_efficiency * .18 +
            site.open_water_score * .20 +
            site.backland_score * .16 +
            natural_bonus -
            distance_cost * .12 -
            scale_mismatch * .18 -
            budget_overrun * .55 +
            jitter
        if site.selection_score > best_score {
            best, best_score = site, site.selection_score
        }
    }
    best.valid = best_score > f32(-1000)
    return best
}

append_contour_point :: proc(contour: ^Contour, point: Vec2) -> bool {
    if contour == nil || contour.count >= len(contour.points) do return false
    contour.points[contour.count] = point
    contour.count += 1
    return true
}

shoreline_sample :: proc(site: ^Harbor_Site, fraction: f32) -> Vec2 {
    if site == nil || site.shoreline.count == 0 do return {}
    if site.shoreline.count == 1 do return site.shoreline.points[0]
    scaled := clamp(fraction, f32(0), f32(1)) * f32(site.shoreline.count - 1)
    first := min(int(scaled), site.shoreline.count - 2)
    blend := scaled - f32(first)
    return add(
        site.shoreline.points[first],
        scale(sub(site.shoreline.points[first + 1], site.shoreline.points[first]), blend),
    )
}

shoreline_outward :: proc(site: ^Harbor_Site, fraction: f32) -> Vec2 {
    before := shoreline_sample(site, max(fraction - .025, f32(0)))
    after := shoreline_sample(site, min(fraction + .025, f32(1)))
    tangent := normalize(sub(after, before))
    outward := Vec2{-tangent.z, tangent.x}
    if dot(outward, site.outward) < 0 do outward = scale(outward, -1)
    return outward
}

append_structure :: proc(
    plan: ^Harbor_Plan,
    kind: Structure_Kind,
    material: Structure_Material,
    width: f32,
    points: ..Vec2,
) -> bool {
    if plan == nil ||
       plan.structure_count >= len(plan.structures) ||
       len(points) < 2 ||
       len(points) > STRUCTURE_POINT_CAPACITY {
        return false
    }
    path := &plan.structures[plan.structure_count]
    path.kind, path.material, path.width = kind, material, width
    for point in points {
        path.points[path.count] = point
        path.count += 1
    }
    plan.structure_count += 1
    return true
}

point_in_contour :: proc(contour: ^Contour, point: Vec2) -> bool {
    if contour == nil || contour.count < 3 do return false
    inside := false
    previous := contour.count - 1
    for current in 0 ..< contour.count {
        a, b := contour.points[current], contour.points[previous]
        crosses := (a.z > point.z) != (b.z > point.z)
        if crosses {
            denominator := b.z - a.z
            if abs(denominator) > .0001 {
                crossing_x := (b.x - a.x) * (point.z - a.z) / denominator + a.x
                if point.x < crossing_x do inside = !inside
            }
        }
        previous = current
    }
    return inside
}

distance_to_segment :: proc(point, a, b: Vec2) -> f32 {
    ab := sub(b, a)
    denominator := dot(ab, ab)
    if denominator <= .0001 do return distance(point, a)
    t := clamp(dot(sub(point, a), ab) / denominator, f32(0), f32(1))
    return distance(point, add(a, scale(ab, t)))
}

point_clears_structures :: proc(plan: ^Harbor_Plan, point: Vec2, clearance: f32) -> bool {
    for structure in plan.structures[:plan.structure_count] {
        for index in 0 ..< structure.count - 1 {
            if distance_to_segment(point, structure.points[index], structure.points[index + 1]) <
               clearance + structure.width * .5 {
                return false
            }
        }
    }
    return true
}

append_berth :: proc(plan: ^Harbor_Plan, berth: Berth) -> bool {
    if plan == nil || plan.berth_count >= len(plan.berths) do return false
    plan.berths[plan.berth_count] = berth
    plan.berth_count += 1
    return true
}

water_ray_extent :: proc(
    project: ^terrain.Project,
    site: ^Harbor_Site,
    shoreline_fraction, maximum_distance: f32,
) -> f32 {
    if project == nil || site == nil do return 0
    shore := shoreline_sample(site, shoreline_fraction)
    outward := shoreline_outward(site, shoreline_fraction)
    usable := f32(7)
    step := f32(5)
    step_count := max(1, int(maximum_distance / step))
    for step_index in 2 ..= step_count {
        distance_meters := min(f32(step_index) * step, maximum_distance)
        point := add(shore, scale(outward, distance_meters))
        height := terrain.sample_surface_height(project, 0, point.x, point.z)
        if height > site.sea_level + .08 do break
        usable = distance_meters
    }
    return usable
}

build_water_envelope :: proc(
    plan: ^Harbor_Plan,
    project: ^terrain.Project,
    site: ^Harbor_Site,
    scale_meters: f32,
    seed: u32,
) {
    if plan == nil || project == nil || site == nil do return
    count := 20
    extents: [20]f32
    maximum_distance := scale_meters * .55
    for index in 0 ..< count {
        t := f32(index) / f32(count - 1)
        extents[index] = water_ray_extent(project, site, t, maximum_distance)
    }
    // Smooth isolated deep-water spikes without smoothing across a shoal or
    // land obstruction. Local minima remain authoritative.
    smoothed := extents
    for index in 1 ..< count - 1 {
        neighborhood := extents[index - 1] * .25 + extents[index] * .5 + extents[index + 1] * .25
        smoothed[index] = min(extents[index], neighborhood)
    }

    minimum := Vec2{100000, 100000}
    maximum := Vec2{-100000, -100000}
    for index in 0 ..< count {
        t := f32(index) / f32(count - 1)
        point := add(shoreline_sample(site, t), scale(shoreline_outward(site, t), 7))
        _ = append_contour_point(&plan.navigable_water, point)
        minimum.x, minimum.z = min(minimum.x, point.x), min(minimum.z, point.z)
        maximum.x, maximum.z = max(maximum.x, point.x), max(maximum.z, point.z)
    }
    for index in 0 ..< count {
        t := f32(count - 1 - index) / f32(count - 1)
        source_index := count - 1 - index
        point := add(shoreline_sample(site, t), scale(shoreline_outward(site, t), smoothed[source_index]))
        _ = append_contour_point(&plan.navigable_water, point)
        minimum.x, minimum.z = min(minimum.x, point.x), min(minimum.z, point.z)
        maximum.x, maximum.z = max(maximum.x, point.x), max(maximum.z, point.z)
    }
    plan.bounds = {minimum, maximum}
}

shore_landfall_is_sound :: proc(project: ^terrain.Project, shore, outward: Vec2, sea_level: f32) -> bool {
    if project == nil do return false
    dry := add(shore, scale(outward, -7))
    wet := add(shore, scale(outward, 7))
    dry_height := terrain.sample_surface_height(project, 0, dry.x, dry.z)
    wet_height := terrain.sample_surface_height(project, 0, wet.x, wet.z)
    return dry_height > sea_level + .08 && wet_height < sea_level + .08
}

breakwater_path_is_sound :: proc(
    project: ^terrain.Project,
    site: ^Harbor_Site,
    harborward_sign: f32,
    points: ..Vec2,
) -> bool {
    if project == nil || site == nil || len(points) < 3 do return false
    first_direction := normalize(sub(points[1], points[0]))
    hook_direction := normalize(sub(points[len(points) - 1], points[len(points) - 2]))
    if dot(first_direction, site.outward) < .42 do return false
    if dot(hook_direction, site.tangent) * harborward_sign < .12 do return false
    if distance(points[0], points[len(points) - 1]) < 28 do return false

    traveled := f32(0)
    for segment_index in 0 ..< len(points) - 1 {
        a, b := points[segment_index], points[segment_index + 1]
        segment_length := distance(a, b)
        sample_count := max(2, int(math.ceil(segment_length / 5)))
        for sample_index in 1 ..= sample_count {
            t := f32(sample_index) / f32(sample_count)
            point := add(a, scale(sub(b, a), t))
            along := traveled + segment_length * t
            // Only the root may occupy dry ground. The remaining mole must
            // cross water rather than clipping a beach or a second headland.
            if along > 10 && terrain.sample_surface_height(project, 0, point.x, point.z) > site.sea_level + .12 {
                return false
            }
        }
        traveled += segment_length
    }
    return true
}

append_shore_following_quay :: proc(
    plan: ^Harbor_Plan,
    project: ^terrain.Project,
    site: ^Harbor_Site,
    first_fraction, last_fraction: f32,
) -> bool {
    if plan == nil || project == nil || site == nil do return false
    points: [STRUCTURE_POINT_CAPACITY]Vec2
    point_count := 6
    for index in 0 ..< point_count {
        t := f32(index) / f32(point_count - 1)
        fraction := first_fraction + (last_fraction - first_fraction) * t
        shore := shoreline_sample(site, fraction)
        outward := shoreline_outward(site, fraction)
        if !shore_landfall_is_sound(project, shore, outward, site.sea_level) do return false
        points[index] = add(shore, scale(outward, .75))
        if index > 0 && distance(points[index - 1], points[index]) > 24 do return false
    }
    if distance(points[0], points[point_count - 1]) > 82 do return false
    return append_structure(plan, .Quay, .Stone, 5, ..points[:point_count])
}

build_protection_and_frontage :: proc(
    plan: ^Harbor_Plan,
    project: ^terrain.Project,
    site: ^Harbor_Site,
    scale_meters: f32,
    seed: u32,
) {
    half := scale_meters * .5
    depth := scale_meters * .5
    west_shore := shoreline_sample(site, .08)
    west_local_outward := shoreline_outward(site, .08)
    west_outward := normalize(add(west_local_outward, scale(site.outward, 1.75)))
    west_tangent := Vec2{west_outward.z, -west_outward.x}
    if dot(west_tangent, site.tangent) < 0 do west_tangent = scale(west_tangent, -1)
    west_start := add(west_shore, scale(west_outward, -5))
    west_knee := add(add(west_start, scale(west_tangent, half * .08)), scale(west_outward, depth * .34))
    west_tip := add(add(west_knee, scale(west_tangent, half * .25)), scale(west_outward, depth * .20))
    east_shore := shoreline_sample(site, .92)
    east_local_outward := shoreline_outward(site, .92)
    east_outward := normalize(add(east_local_outward, scale(site.outward, 1.75)))
    east_tangent := Vec2{east_outward.z, -east_outward.x}
    if dot(east_tangent, site.tangent) < 0 do east_tangent = scale(east_tangent, -1)
    east_start := add(east_shore, scale(east_outward, -5))
    east_knee := add(add(east_start, scale(east_tangent, -half * .08)), scale(east_outward, depth * .30))
    east_tip := add(add(east_knee, scale(east_tangent, -half * .30)), scale(east_outward, depth * .17))
    west_sound :=
        shore_landfall_is_sound(project, west_shore, west_outward, site.sea_level) &&
        breakwater_path_is_sound(project, site, 1, west_start, west_knee, west_tip) &&
        world_to_local(site.anchor, site.tangent, site.outward, west_tip).x < -10
    east_sound :=
        shore_landfall_is_sound(project, east_shore, east_outward, site.sea_level) &&
        breakwater_path_is_sound(project, site, -1, east_start, east_knee, east_tip) &&
        world_to_local(site.anchor, site.tangent, site.outward, east_tip).x > 10
    if west_sound && east_sound && distance(west_tip, east_tip) < 28 {
        // Preserve the better natural landfall as a single-mole harbor rather
        // than accepting a pinched or accidentally closed entrance.
        if site.curvature_score >= 0 {
            east_sound = false
        } else {
            west_sound = false
        }
    }
    if west_sound {
        _ = append_structure(plan, .Breakwater, .Rubble, 11, west_start, west_knee, west_tip)
    }
    if east_sound && plan.archetype != .Open_Mooring_Harbor {
        _ = append_structure(plan, .Breakwater, .Rubble, 10, east_start, east_knee, east_tip)
    }
    plan.entrance =
        west_sound && east_sound ? scale(add(west_tip, east_tip), .5) : west_sound ? add(west_tip, scale(site.tangent, half * .28)) : east_sound ? add(east_tip, scale(site.tangent, -half * .28)) : add(site.anchor, scale(site.outward, depth * .72))

    frontage_count := plan.archetype == .Fishing_Cove ? 2 : 3
    for index in 0 ..< frontage_count {
        t0 := f32(index) / f32(frontage_count)
        t1 := f32(index + 1) / f32(frontage_count)
        fa, fb := .18 + t0 * .64 + .012, .18 + t1 * .64 - .025
        _ = append_shore_following_quay(plan, project, site, fa, fb)
    }
}

cross_2d :: #force_inline proc(a, b: Vec2) -> f32 {
    return a.x * b.z - a.z * b.x
}

segments_cross :: proc(a, b, c, d: Vec2) -> bool {
    ab, cd := sub(b, a), sub(d, c)
    denominator := cross_2d(ab, cd)
    if abs(denominator) <= .0001 do return false
    ac := sub(c, a)
    t := cross_2d(ac, cd) / denominator
    u := cross_2d(ac, ab) / denominator
    return t > .001 && t < .999 && u > .001 && u < .999
}

segment_crosses_contour :: proc(a, b: Vec2, contour: ^Contour) -> bool {
    if contour == nil || contour.count < 3 do return false
    if point_in_contour(contour, b) do return true
    for index in 0 ..< contour.count {
        next := (index + 1) % contour.count
        if segments_cross(a, b, contour.points[index], contour.points[next]) do return true
    }
    return false
}

pier_path_is_sound :: proc(
    plan: ^Harbor_Plan,
    project: ^terrain.Project,
    site: ^Harbor_Site,
    root, tip: Vec2,
) -> bool {
    if plan == nil || project == nil || site == nil do return false
    delta := sub(tip, root)
    pier_length := length(delta)
    if pier_length < 24 || pier_length > 68 do return false

    for sample_index in 6 ..= 12 {
        t := f32(sample_index) / 12
        point := add(root, scale(delta, t))
        if terrain.sample_surface_height(project, 0, point.x, point.z) > site.sea_level + .20 do return false
        for structure in plan.structures[:plan.structure_count] {
            for point_index in 0 ..< structure.count - 1 {
                a, b := structure.points[point_index], structure.points[point_index + 1]
                if structure.kind == .Quay && distance_to_segment(root, a, b) <= 12 do continue
                if segments_cross(root, tip, a, b) && distance_to_segment(root, a, b) > 7 do return false
                if t >= .35 && distance_to_segment(point, a, b) < structure.width * .5 + 4 do return false
            }
        }
    }
    return true
}

build_piers_and_slips :: proc(
    plan: ^Harbor_Plan,
    project: ^terrain.Project,
    site: ^Harbor_Site,
    scale_meters: f32,
    seed: u32,
) {
    if plan.archetype == .Open_Mooring_Harbor do return
    pier_count := plan.archetype == .Fishing_Cove ? 2 : 3 + int(seed & 1)
    for pier_index in 0 ..< pier_count {
        fraction := f32(pier_index + 1) / f32(pier_count + 1)
        shore_fraction := .22 + fraction * .56
        // Preserve the central approach corridor before attempting geometry.
        // Side-waterfront piers read as incremental growth rather than spokes.
        if shore_fraction > .43 && shore_fraction < .57 do continue
        shore := shoreline_sample(site, shore_fraction)
        local_outward := shoreline_outward(site, shore_fraction)
        pier_outward := normalize(add(local_outward, scale(site.outward, .65)))
        local_tangent := Vec2{pier_outward.z, -pier_outward.x}
        yaw_bias := (random_unit(seed + u32(pier_index) * 71) - .5) * .12
        dry_root := add(shore, scale(local_outward, -5))
        if terrain.sample_surface_height(project, 0, dry_root.x, dry_root.z) <= site.sea_level do continue
        root := add(shore, scale(pier_outward, .75))
        requested_length := clamp(
            scale_meters * (.17 + random_unit(seed + u32(pier_index) * 97) * .06),
            f32(26),
            f32(65),
        )
        tip := add(root, add(scale(pier_outward, requested_length), scale(local_tangent, yaw_bias * requested_length)))
        if !pier_path_is_sound(plan, project, site, root, tip) do continue
        if !append_structure(plan, .Pier, .Timber, 2.2, root, tip) do continue
        delta := normalize(sub(tip, root))
        normal := Vec2{-delta.z, delta.x}
        pier_length := distance(root, tip)
        berth_count := max(2, int(pier_length / 18))
        for berth_index in 1 ..= berth_count {
            t := f32(berth_index) / f32(berth_count + 1)
            center := add(root, scale(sub(tip, root), t))
            for side in -1 ..= 1 {
                if side == 0 do continue
                position := add(center, scale(normal, f32(side) * 6))
                yaw := math.atan2(delta.x, delta.z)
                if side < 0 do yaw += math.PI
                _ = append_berth(
                    plan,
                    {
                        position = position,
                        yaw = yaw,
                        class = (berth_index + pier_index) & 1 == 0 ? boats.Class.Sail : boats.Class.Motor,
                        kind = .Slip,
                        occupied = (mix_seed(seed + u32(berth_index * 31 + pier_index * 73 + side + 2)) & 3) != 0,
                        clearance_radius = 5.5,
                    },
                )
            }
        }
    }
}

build_fairways :: proc(plan: ^Harbor_Plan, site: ^Harbor_Site, scale_meters: f32) {
    half_width := max(f32(18), scale_meters * .07)
    center := local_to_world(site.anchor, site.tangent, site.outward, {0, scale_meters * .27})
    _ = append_contour_point(&plan.turning_basin, add(center, scale(site.tangent, -half_width)))
    _ = append_contour_point(&plan.turning_basin, add(center, scale(site.outward, half_width)))
    _ = append_contour_point(&plan.turning_basin, add(center, scale(site.tangent, half_width)))
    _ = append_contour_point(&plan.turning_basin, add(center, scale(site.outward, -half_width)))
    inner := local_to_world(site.anchor, site.tangent, site.outward, {0, 14})
    corridor := max(f32(14), scale_meters * .045)
    _ = append_contour_point(&plan.fairway, add(inner, scale(site.tangent, -corridor)))
    _ = append_contour_point(&plan.fairway, add(plan.entrance, scale(site.tangent, -corridor)))
    _ = append_contour_point(&plan.fairway, add(plan.entrance, scale(site.tangent, corridor)))
    _ = append_contour_point(&plan.fairway, add(inner, scale(site.tangent, corridor)))
}

build_moorings :: proc(plan: ^Harbor_Plan, site: ^Harbor_Site, scale_meters: f32, seed: u32) {
    desired := plan.archetype == .Open_Mooring_Harbor ? 28 : 12
    half := scale_meters * .5
    minimum_spacing := f32(22)
    for attempt in 0 ..< 768 {
        if plan.berth_count >= BERTH_CAPACITY || desired <= 0 do break
        random_seed := mix_seed(seed ~ u32(attempt * 0x9e37))
        x := (random_unit(random_seed) * 2 - 1) * half * .66
        z_fraction := random_unit(random_seed ~ 0x51ed_270b)
        z := scale_meters * (.17 + z_fraction * .26)
        x += math.sin(z / max(scale_meters, f32(1)) * math.PI * 3) * scale_meters * .035
        point := local_to_world(site.anchor, site.tangent, site.outward, {x, z})
        if !point_in_contour(&plan.navigable_water, point) do continue
        if point_in_contour(&plan.fairway, point) || point_in_contour(&plan.turning_basin, point) do continue
        if !point_clears_structures(plan, point, 11) do continue
        clear := true
        for berth in plan.berths[:plan.berth_count] {
            required := berth.kind == .Swing_Mooring ? minimum_spacing : f32(14)
            if distance(point, berth.position) < required {
                clear = false
                break
            }
        }
        if !clear do continue
        yaw := (random_unit(random_seed ~ 0xa341_316c) - .5) * .28
        _ = append_berth(
            plan,
            {
                position = point,
                yaw = yaw,
                class = (attempt & 1) == 0 ? boats.Class.Sail : boats.Class.Motor,
                kind = .Swing_Mooring,
                occupied = (random_seed & 3) != 0,
                clearance_radius = minimum_spacing * .5,
            },
        )
        desired -= 1
    }
}

route_has_water_depth :: proc(project: ^terrain.Project, plan: ^Harbor_Plan, route: ^Route) -> bool {
    if project == nil || plan == nil || route == nil || route.count < 2 do return false
    for segment_index in 0 ..< route.count - 1 {
        a, b := route.points[segment_index], route.points[segment_index + 1]
        segment_length := distance(a, b)
        sample_count := max(2, int(math.ceil(segment_length / 8)))
        for sample_index in 0 ..= sample_count {
            t := f32(sample_index) / f32(sample_count)
            point := add(a, scale(sub(b, a), t))
            if terrain.sample_surface_height(project, 0, point.x, point.z) > plan.sea_level + .12 {
                return false
            }
        }
    }
    return true
}

build_routes :: proc(plan: ^Harbor_Plan, project: ^terrain.Project, site: ^Harbor_Site, scale_meters: f32) {
    if plan == nil || project == nil || site == nil do return
    plan.routes = {}
    plan.route_count = 0
    open_water := local_to_world(site.anchor, site.tangent, site.outward, {scale_meters * .08, scale_meters * .66})
    turning := local_to_world(site.anchor, site.tangent, site.outward, {0, scale_meters * .27})
    for berth_index in 0 ..< plan.berth_count {
        berth := &plan.berths[berth_index]
        if !berth.occupied do continue
        if plan.route_count >= ROUTE_CAPACITY {
            berth.occupied = false
            continue
        }
        route := &plan.routes[plan.route_count]
        route.berth_index = berth_index
        route.points[0] = open_water
        route.points[1] = plan.entrance
        route.points[2] = add(
            scale(add(plan.entrance, turning), .5),
            scale(site.tangent, (f32(berth_index & 3) - 1.5) * 2.5),
        )
        route.points[3] = turning
        berth_delta := sub(berth.position, turning)
        route.points[4] = add(turning, scale(berth_delta, .62))
        route.points[5] = berth.position
        route.count = 6
        if !route_has_water_depth(project, plan, route) {
            route^ = {}
            berth.occupied = false
            continue
        }
        plan.route_count += 1
    }
}

reserve_bounded_terrain_edits :: proc(plan: ^Harbor_Plan, project: ^terrain.Project) {
    if plan == nil || project == nil || plan.route_count == 0 do return
    route := &plan.routes[0]
    for point_index in 1 ..< route.count - 1 {
        if plan.terrain_edit_count >= TERRAIN_EDIT_CAPACITY do break
        point := route.points[point_index]
        current, _, _, found := terrain.sample_bathymetry(project, point.x, point.z)
        if !found do current = project.sea_level - terrain.DEEP_OCEAN_DEPTH
        target := project.sea_level - 1.2
        if current <= target do continue
        plan.terrain_edits[plan.terrain_edit_count] = {
            kind     = .Dredge,
            center   = point,
            radius   = 12,
            target_y = target,
            feather  = 8,
        }
        plan.terrain_edit_count += 1
    }
    // Quays may make a small, feathered working pad at the water's edge, but
    // never reshape a broad section of coast to force an unsuitable layout.
    for structure in plan.structures[:plan.structure_count] {
        if plan.terrain_edit_count >= TERRAIN_EDIT_CAPACITY do break
        if structure.kind != .Quay || structure.count < 2 do continue
        a, b := structure.points[0], structure.points[structure.count - 1]
        midpoint := scale(add(a, b), .5)
        current := terrain.sample_surface_height(project, 0, midpoint.x, midpoint.z)
        target := project.sea_level + .18
        if abs(current - target) <= .2 do continue
        plan.terrain_edits[plan.terrain_edit_count] = {
            kind     = current < target ? Terrain_Edit_Kind.Fill : Terrain_Edit_Kind.Cut,
            center   = midpoint,
            radius   = min(distance(a, b) * .22, f32(9)),
            target_y = target,
            feather  = 5,
        }
        plan.terrain_edit_count += 1
    }
}

apply_terrain_edits :: proc(project: ^terrain.Project, plan: ^Harbor_Plan) {
    if project == nil || plan == nil || !plan.valid do return
    for edit in plan.terrain_edits[:plan.terrain_edit_count] {
        if edit.kind == .Dredge {
            terrain.apply_bathymetry_level(
                project,
                edit.center.x,
                edit.center.z,
                edit.radius,
                edit.target_y,
                edit.feather,
                .Harbor,
            )
            continue
        }
        current := terrain.sample_surface_height(project, 0, edit.center.x, edit.center.z)
        delta := edit.target_y - current
        if abs(delta) <= .01 do continue
        terrain.apply_stroke_with_hardness(
            project,
            .Raise,
            edit.center.x,
            edit.center.z,
            edit.radius + edit.feather,
            abs(delta),
            delta < 0 ? f32(-1) : f32(1),
            clamp(edit.radius / max(edit.radius + edit.feather, f32(.01)), f32(0), f32(1)),
        )
    }
}

mooring_lattice_matches :: proc(plan: ^Harbor_Plan) -> int {
    matches := 0
    for a_index in 0 ..< plan.berth_count {
        a := plan.berths[a_index]
        if a.kind != .Swing_Mooring do continue
        for b_index in a_index + 1 ..< plan.berth_count {
            b := plan.berths[b_index]
            if b.kind != .Swing_Mooring do continue
            ab := sub(b.position, a.position)
            for c_index in b_index + 1 ..< plan.berth_count {
                c := plan.berths[c_index]
                if c.kind != .Swing_Mooring do continue
                ac := sub(c.position, a.position)
                if abs(dot(normalize(ab), normalize(ac))) > .12 do continue
                expected := add(b.position, ac)
                for d_index in c_index + 1 ..< plan.berth_count {
                    d := plan.berths[d_index]
                    if d.kind == .Swing_Mooring && distance(d.position, expected) < 2.5 {
                        matches += 1
                    }
                }
            }
        }
    }
    return matches
}

validate_harbor :: proc(project: ^terrain.Project, plan: ^Harbor_Plan) -> Harbor_Diagnostics {
    diagnostics: Harbor_Diagnostics
    if project == nil || plan == nil do return diagnostics
    diagnostics.footprint_diameter = distance(plan.bounds.minimum, plan.bounds.maximum)
    diagnostics.minimum_depth = 1000
    diagnostics.shelter_score = .75
    occupied_count := 0
    diagnostics.naturalism_score = .8
    diagnostics.rectangularity = .72
    diagnostics.mooring_lattice_matches = mooring_lattice_matches(plan)
    diagnostics.capacity_exceeded = plan.structure_count >= STRUCTURE_CAPACITY || plan.berth_count >= BERTH_CAPACITY
    for berth in plan.berths[:plan.berth_count] {
        if berth.occupied do occupied_count += 1
        depth := terrain.sample_water_interface(project, berth.position.x, berth.position.z).depth
        diagnostics.minimum_depth = min(diagnostics.minimum_depth, depth)
        if depth < -.05 || !point_in_contour(&plan.navigable_water, berth.position) {
            diagnostics.clearance_failures += 1
        }
    }
    for &route in plan.routes[:plan.route_count] {
        if route.berth_index < 0 ||
           route.berth_index >= plan.berth_count ||
           route.count < 2 ||
           distance(route.points[route.count - 1], plan.berths[route.berth_index].position) > 1 ||
           !route_has_water_depth(project, plan, &route) {
            diagnostics.route_failures += 1
        }
    }
    if plan.route_count != occupied_count {
        diagnostics.route_failures += abs(plan.route_count - occupied_count)
    }
    diagnostics.navigation_score =
        occupied_count > 0 ? clamp(f32(plan.route_count - diagnostics.route_failures) / f32(occupied_count), 0, 1) : 0
    diagnostics.valid =
        diagnostics.footprint_diameter >= MIN_DIAMETER_METERS &&
        diagnostics.footprint_diameter <= MAX_DIAMETER_METERS * 1.35 &&
        plan.structure_count >= 2 &&
        plan.berth_count >= 6 &&
        plan.route_count > 0 &&
        diagnostics.route_failures == 0 &&
        diagnostics.clearance_failures == 0 &&
        diagnostics.mooring_lattice_matches == 0 &&
        !diagnostics.capacity_exceeded
    return diagnostics
}

generate_candidate :: proc(
    project: ^terrain.Project,
    site: ^Harbor_Site,
    role: Settlement_Role,
    seed: u32,
    candidate_index: int,
) -> Harbor_Plan {
    plan: Harbor_Plan
    if project == nil || site == nil || !site.valid do return plan
    candidate_seed := mix_seed(seed ~ u32(candidate_index) * 0x9e37_79b9)
    plan.seed = seed
    plan.generation_version = GENERATION_VERSION
    plan.archetype = Archetype((int(seed % 5) + candidate_index) % 5)
    if role == .Working_Port && candidate_index & 1 == 0 do plan.archetype = .Quay_Harbor
    plan.origin, plan.tangent, plan.outward = site.anchor, site.tangent, site.outward
    plan.sea_level = site.sea_level
    plan.shoreline = site.shoreline
    scale_variation := .86 + random_unit(candidate_seed) * .28
    scale_meters := clamp(site.preferred_scale * scale_variation, MIN_DIAMETER_METERS, MAX_DIAMETER_METERS)
    build_water_envelope(&plan, project, site, scale_meters, candidate_seed)
    build_protection_and_frontage(&plan, project, site, scale_meters, candidate_seed)
    build_fairways(&plan, site, scale_meters)
    build_piers_and_slips(&plan, project, site, scale_meters, candidate_seed)
    build_moorings(&plan, site, scale_meters, candidate_seed)
    build_routes(&plan, project, site, scale_meters)
    reserve_bounded_terrain_edits(&plan, project)
    office_shore := shoreline_sample(site, .34)
    plan.office = add(office_shore, scale(site.outward, -18))
    plan.settlement_connection = add(office_shore, scale(site.outward, -48))
    plan.diagnostics = validate_harbor(project, &plan)
    plan.valid = plan.diagnostics.valid
    return plan
}

generate_for_coast :: proc(
    project: ^terrain.Project,
    site: ^Harbor_Site,
    role: Settlement_Role,
    seed: u32,
) -> Harbor_Plan {
    best: Harbor_Plan
    best_score := f32(-1)
    for candidate_index in 0 ..< CANDIDATE_COUNT {
        candidate := generate_candidate(project, site, role, seed, candidate_index)
        score :=
            candidate.diagnostics.shelter_score * .35 +
            candidate.diagnostics.navigation_score * .35 +
            candidate.diagnostics.naturalism_score * .30
        if candidate.valid && (!best.valid || score > best_score) {
            best, best_score = candidate, score
        } else if !best.valid && score > best_score {
            best, best_score = candidate, score
        }
    }
    return best
}

Strategy_Estimate :: struct {
    feasible: bool,
    capacity: int,
    shelter:  f32,
    cost:     f32,
}

estimate_strategy :: proc(
    site: ^Harbor_Site,
    program: ^Harbor_Program,
    strategy: Harbor_Strategy,
) -> Strategy_Estimate {
    result: Strategy_Estimate
    if site == nil || program == nil do return result
    natural_shelter := clamp(1 - site.exposure_score, 0, 1)
    scale_meters := clamp(site.preferred_scale, MIN_DIAMETER_METERS, MAX_DIAMETER_METERS)
    convex_exposed := site.curvature_score < .02 && site.exposure_score > .62
    switch strategy {
    case .Natural_Anchorage:
        result.feasible = site.open_water_score >= .58
        result.capacity = clamp(int(scale_meters / 13 * site.open_water_score), 4, 32)
        result.shelter = natural_shelter
        result.cost = .02 + site.exposure_score * .04
    case .Beach_Landing:
        result.feasible = site.backland_score >= .25 && site.open_water_score >= .42
        result.capacity = clamp(int(scale_meters / 28 * max(site.backland_score, f32(.4))), 4, 16)
        result.shelter = clamp(natural_shelter + .02, 0, 1)
        result.cost = .07 + site.slope_score * .10
    case .Shoreline_Quay:
        result.feasible = !convex_exposed && site.backland_score >= .35 && site.curvature_score > -.10
        result.capacity = clamp(int(scale_meters / 11 * (.65 + site.backland_score * .5)), 8, 42)
        result.shelter = clamp(natural_shelter + .06 + max(site.curvature_score, f32(0)) * .18, 0, 1)
        result.cost = .14 + site.construction_cost * .22
    case .Single_Hooked_Mole:
        result.feasible =
            (!convex_exposed || program.allow_major_works) &&
            site.open_water_score >= .45 &&
            (site.opportunity == .Headland || site.opportunity == .Lee_Shore || site.curvature_score > .05)
        result.capacity = clamp(int(scale_meters / 8.5 * (.72 + site.backland_score * .35)), 12, 58)
        result.shelter = clamp(natural_shelter + .22 + max(site.curvature_score, f32(0)) * .08, 0, 1)
        result.cost = .28 + site.exposure_score * .28 + site.slope_score * .08
    case .Offset_Twin_Moles:
        result.feasible =
            (!convex_exposed || program.allow_major_works) &&
            site.open_water_score >= .40 &&
            site.curvature_score > .02
        result.capacity = clamp(int(scale_meters / 6.5 * (.82 + site.backland_score * .3)), 20, 84)
        result.shelter = clamp(natural_shelter + .36, 0, 1)
        result.cost = .45 + site.exposure_score * .22 + site.slope_score * .06
    case .Dredged_Basin:
        result.feasible =
            (!convex_exposed || program.allow_major_works) &&
            site.open_water_score >= .35 &&
            site.open_water_score < .75 &&
            site.slope_score < .75
        result.capacity = clamp(int(scale_meters / 6 * (.86 + site.backland_score * .28)), 24, 96)
        result.shelter = clamp(natural_shelter + .32, 0, 1)
        result.cost = .52 + (1 - site.open_water_score) * .28 + site.slope_score * .06
    case .Excavated_Pocket:
        result.feasible = program.allow_major_works && site.slope_score < .55 && site.backland_score >= .30
        result.capacity = clamp(int(scale_meters / 5.5 * (.9 + site.backland_score * .25)), 28, 96)
        result.shelter = clamp(natural_shelter + .45, 0, 1)
        result.cost = .72 + site.slope_score * .25
    case .Reclaimed_Port:
        result.feasible = program.allow_major_works && site.backland_score >= .45 && site.open_water_score >= .42
        result.capacity = clamp(int(scale_meters / 4.5 * (.88 + site.backland_score * .2)), 32, 96)
        result.shelter = clamp(natural_shelter + .38, 0, 1)
        result.cost = .82 + site.slope_score * .12
    }
    result.feasible = result.feasible && result.cost <= program.construction_budget
    return result
}

choose_strategy :: proc(site: ^Harbor_Site, program: ^Harbor_Program) -> (Harbor_Strategy, bool, int) {
    if site == nil || program == nil do return .Natural_Anchorage, true, 1
    previous_demand := -1
    for downgrade_step in 0 ..= 5 {
        demand := max(program.minimum_capacity, program.target_capacity >> uint(downgrade_step))
        if demand == previous_demand do break
        previous_demand = demand
        shelter_requirement := max(program.shelter_requirement - f32(downgrade_step) * .08, f32(.34))
        for strategy_index in 0 ..= int(Harbor_Strategy.Reclaimed_Port) {
            strategy := Harbor_Strategy(strategy_index)
            estimate := estimate_strategy(site, program, strategy)
            if estimate.feasible && estimate.capacity >= demand && estimate.shelter >= shelter_requirement {
                return strategy, downgrade_step > 0, downgrade_step
            }
        }
    }
    return .Beach_Landing, true, 5
}

strategy_keeps_structure :: proc(strategy: Harbor_Strategy, kind: Structure_Kind, breakwater_index: int) -> bool {
    switch strategy {
    case .Natural_Anchorage:
        return false
    case .Beach_Landing:
        return kind == .Quay
    case .Shoreline_Quay:
        return kind == .Quay || kind == .Pier
    case .Single_Hooked_Mole:
        return kind != .Breakwater || breakwater_index == 0
    case .Offset_Twin_Moles, .Dredged_Basin, .Excavated_Pocket, .Reclaimed_Port:
        return true
    }
    return true
}

slip_has_structure_support :: proc(plan: ^Harbor_Plan, berth: Berth) -> bool {
    if plan == nil || berth.kind != .Slip do return berth.kind != .Slip
    for structure in plan.structures[:plan.structure_count] {
        if structure.kind != .Pier && structure.kind != .Quay && structure.kind != .Natural_Jetty do continue
        for point_index in 0 ..< structure.count - 1 {
            clearance := structure.width * .5 + berth.clearance_radius + 3
            if distance_to_segment(berth.position, structure.points[point_index], structure.points[point_index + 1]) <=
               clearance {
                return true
            }
        }
    }
    return false
}

shape_runtime_for_strategy :: proc(plan: ^Harbor_Plan, strategy: Harbor_Strategy, capacity: int) {
    if plan == nil do return
    compacted: [STRUCTURE_CAPACITY]Structure_Path
    compacted_count, breakwater_index := 0, 0
    // Historical ordering: inherited waterfront, later pier extensions, then
    // protective works. Phase metadata can therefore address each contiguous
    // construction campaign without inventing an optimized global layout.
    kinds := [3]Structure_Kind{.Quay, .Pier, .Breakwater}
    for desired_kind in kinds {
        for structure in plan.structures[:plan.structure_count] {
            if structure.kind != desired_kind do continue
            keep := strategy_keeps_structure(strategy, structure.kind, breakwater_index)
            if structure.kind == .Breakwater do breakwater_index += 1
            if keep && compacted_count < len(compacted) {
                compacted[compacted_count] = structure
                compacted_count += 1
            }
        }
    }
    // Preserve any future structure kinds after the historical core ordering.
    for structure in plan.structures[:plan.structure_count] {
        if structure.kind == .Quay || structure.kind == .Breakwater || structure.kind == .Pier do continue
        if strategy_keeps_structure(strategy, structure.kind, breakwater_index) && compacted_count < len(compacted) {
            compacted[compacted_count] = structure
            compacted_count += 1
        }
    }
    plan.structures = compacted
    plan.structure_count = compacted_count
    berth_limit := min(plan.berth_count, max(capacity, 4))
    if strategy == .Natural_Anchorage || strategy == .Beach_Landing {
        moorings: [BERTH_CAPACITY]Berth
        mooring_count := 0
        for berth in plan.berths[:plan.berth_count] {
            if berth.kind != .Swing_Mooring || mooring_count >= berth_limit do continue
            moorings[mooring_count] = berth
            mooring_count += 1
        }
        plan.berths = moorings
        plan.berth_count = mooring_count
    } else {
        supported: [BERTH_CAPACITY]Berth
        supported_count := 0
        for berth in plan.berths[:plan.berth_count] {
            if supported_count >= berth_limit do break
            if berth.kind == .Slip && !slip_has_structure_support(plan, berth) do continue
            supported[supported_count] = berth
            supported_count += 1
        }
        plan.berths = supported
        plan.berth_count = supported_count
    }
}

count_structure_kind :: proc(plan: ^Harbor_Plan, kind: Structure_Kind) -> int {
    if plan == nil do return 0
    count := 0
    for structure in plan.structures[:plan.structure_count] {
        if structure.kind == kind do count += 1
    }
    return count
}

repair_strategy_after_structure_rejection :: proc(intervention: ^Harbor_Intervention) {
    if intervention == nil do return
    plan := &intervention.runtime_plan
    breakwaters := count_structure_kind(plan, .Breakwater)
    quays := count_structure_kind(plan, .Quay)
    replacement := intervention.strategy
    #partial switch intervention.strategy {
    case .Offset_Twin_Moles:
        if breakwaters == 1 do replacement = .Single_Hooked_Mole
        if breakwaters == 0 do replacement = quays > 0 ? Harbor_Strategy.Shoreline_Quay : Harbor_Strategy.Beach_Landing
    case .Single_Hooked_Mole:
        if breakwaters == 0 do replacement = quays > 0 ? Harbor_Strategy.Shoreline_Quay : Harbor_Strategy.Beach_Landing
    case .Shoreline_Quay:
        if quays == 0 do replacement = .Beach_Landing
    }
    if replacement != intervention.strategy {
        intervention.strategy = replacement
        intervention.downgraded = true
        intervention.downgrade_steps = max(intervention.downgrade_steps, 1)
    }
}

terrain_edit_allowed_for_strategy :: proc(strategy: Harbor_Strategy, kind: Terrain_Edit_Kind) -> bool {
    switch strategy {
    case .Natural_Anchorage, .Beach_Landing:
        return false
    case .Shoreline_Quay, .Single_Hooked_Mole, .Offset_Twin_Moles:
        return kind == .Cut || kind == .Fill || kind == .Feather
    case .Dredged_Basin, .Excavated_Pocket, .Reclaimed_Port:
        return true
    }
    return false
}

terrain_area_factor :: proc(strategy: Harbor_Strategy) -> f32 {
    switch strategy {
    case .Natural_Anchorage, .Beach_Landing:
        return 0
    case .Shoreline_Quay:
        return .008
    case .Single_Hooked_Mole:
        return .012
    case .Offset_Twin_Moles:
        return .018
    case .Dredged_Basin:
        return .045
    case .Excavated_Pocket:
        return .080
    case .Reclaimed_Port:
        return .120
    }
    return 0
}

shape_terrain_edits_for_strategy :: proc(project: ^terrain.Project, intervention: ^Harbor_Intervention) {
    if project == nil || intervention == nil do return
    plan := &intervention.runtime_plan
    diameter := clamp(plan.diagnostics.footprint_diameter, MIN_DIAMETER_METERS, MAX_DIAMETER_METERS)
    budget_scale := .55 + intervention.program.construction_budget * .45
    intervention.terrain_area_limit = diameter * diameter * terrain_area_factor(intervention.strategy) * budget_scale
    intervention.terrain_volume_limit =
        intervention.terrain_area_limit * (1.2 + intervention.program.construction_budget * 1.8)

    accepted: [TERRAIN_EDIT_CAPACITY]Terrain_Edit
    accepted_count := 0
    for edit in plan.terrain_edits[:plan.terrain_edit_count] {
        if !terrain_edit_allowed_for_strategy(intervention.strategy, edit.kind) do continue
        area := math.PI * edit.radius * edit.radius
        current: f32
        if edit.kind == .Dredge {
            found: bool
            current, _, _, found = terrain.sample_bathymetry(project, edit.center.x, edit.center.z)
            if !found do current = project.sea_level - terrain.DEEP_OCEAN_DEPTH
        } else {
            current = terrain.sample_surface_height(project, 0, edit.center.x, edit.center.z)
        }
        volume := abs(current - edit.target_y) * area * .45
        next_area := intervention.terrain_edit_area + area
        next_cut := intervention.cut_volume
        next_fill := intervention.fill_volume
        if edit.kind == .Dredge || edit.kind == .Cut do next_cut += volume
        if edit.kind == .Fill do next_fill += volume
        next_volume := next_cut + next_fill
        if next_area > intervention.terrain_area_limit || next_volume > intervention.terrain_volume_limit {
            intervention.terrain_budget_exceeded = true
            continue
        }
        accepted[accepted_count] = edit
        accepted_count += 1
        intervention.terrain_edit_area = next_area
        intervention.cut_volume = next_cut
        intervention.fill_volume = next_fill
        if edit.kind == .Dredge do intervention.dredged_area += area
    }
    plan.terrain_edits = accepted
    plan.terrain_edit_count = accepted_count
}

append_waterfront_zone :: proc(
    intervention: ^Harbor_Intervention,
    use: Waterfront_Use,
    center, landward: Vec2,
    width, depth: f32,
) {
    if intervention == nil || intervention.waterfront_count >= WATERFRONT_ZONE_CAPACITY do return
    intervention.waterfront_zones[intervention.waterfront_count] = {use, center, width, depth, landward}
    intervention.waterfront_count += 1
}

build_intervention_history :: proc(intervention: ^Harbor_Intervention) {
    if intervention == nil do return
    plan := &intervention.runtime_plan
    quay_count, breakwater_count, pier_count := 0, 0, 0
    slip_count := 0
    for structure in plan.structures[:plan.structure_count] {
        switch structure.kind {
        case .Quay:
            quay_count += 1
        case .Breakwater:
            breakwater_count += 1
        case .Pier, .Natural_Jetty:
            pier_count += 1
        }
    }
    for berth in plan.berths[:plan.berth_count] {
        if berth.kind == .Slip do slip_count += 1
    }
    if quay_count > 0 {
        intervention.phases[intervention.phase_count] = {
            kind            = .Original_Landing,
            structure_first = 0,
            structure_count = min(quay_count, 1),
        }
        intervention.phase_count += 1
    }
    if breakwater_count > 0 {
        intervention.phases[intervention.phase_count] = {
            kind            = .First_Protection,
            structure_first = quay_count + pier_count,
            structure_count = breakwater_count,
            terrain_first   = 0,
            terrain_count   = min(plan.terrain_edit_count, 2),
        }
        intervention.phase_count += 1
    }
    if quay_count + pier_count > 1 {
        early_pier_count := min(pier_count, 1)
        intervention.phases[intervention.phase_count] = {
            kind            = .Working_Extension,
            structure_first = min(1, quay_count),
            structure_count = max(quay_count - 1, 0) + early_pier_count,
            berth_first     = 0,
            berth_count     = slip_count,
        }
        intervention.phase_count += 1
    }
    if pier_count > 1 && intervention.phase_count < HISTORICAL_PHASE_CAPACITY {
        intervention.phases[intervention.phase_count] = {
            kind            = .Modernization,
            structure_first = quay_count + 1,
            structure_count = pier_count - 1,
        }
        intervention.phase_count += 1
    }
    if plan.berth_count > slip_count && intervention.phase_count < HISTORICAL_PHASE_CAPACITY {
        intervention.phases[intervention.phase_count] = {
            kind        = .Overflow_Moorings,
            berth_first = slip_count,
            berth_count = plan.berth_count - slip_count,
        }
        intervention.phase_count += 1
    }
}

validate_intervention :: proc(project: ^terrain.Project, intervention: ^Harbor_Intervention) -> Harbor_Diagnostics {
    diagnostics: Harbor_Diagnostics
    if project == nil || intervention == nil do return diagnostics
    plan := &intervention.runtime_plan
    diagnostics = validate_harbor(project, plan)
    minimum_structures :=
        intervention.strategy == .Natural_Anchorage || intervention.strategy == .Beach_Landing ? 0 : 2
    required_works_present := true
    #partial switch intervention.strategy {
    case .Shoreline_Quay:
        required_works_present = count_structure_kind(plan, .Quay) > 0
    case .Single_Hooked_Mole:
        required_works_present = count_structure_kind(plan, .Breakwater) == 1
    case .Offset_Twin_Moles:
        required_works_present = count_structure_kind(plan, .Breakwater) == 2
    }
    diagnostics.valid =
        plan.berth_count >= intervention.program.minimum_capacity &&
        plan.structure_count >= minimum_structures &&
        required_works_present &&
        intervention.construction_cost <= intervention.program.construction_budget + .001 &&
        intervention.terrain_edit_area <= intervention.terrain_area_limit + .01 &&
        intervention.cut_volume + intervention.fill_volume <= intervention.terrain_volume_limit + .01 &&
        plan.route_count > 0 &&
        diagnostics.clearance_failures == 0 &&
        diagnostics.mooring_lattice_matches == 0
    return diagnostics
}

generate_intervention :: proc(
    project: ^terrain.Project,
    site: ^Harbor_Site,
    program: ^Harbor_Program,
    seed: u32,
) -> Harbor_Intervention {
    intervention: Harbor_Intervention
    if project == nil || site == nil || program == nil || !site.valid do return intervention
    intervention.seed = seed
    intervention.site = site^
    intervention.program = program^
    intervention.strategy, intervention.downgraded, intervention.downgrade_steps = choose_strategy(site, program)
    achieved_target := program.target_capacity
    if intervention.downgraded {
        achieved_target = max(program.minimum_capacity, program.target_capacity >> uint(intervention.downgrade_steps))
    }
    intervention.runtime_plan = generate_for_coast(project, site, program.role, seed)
    if !intervention.runtime_plan.valid do return intervention
    shape_runtime_for_strategy(&intervention.runtime_plan, intervention.strategy, achieved_target)
    repair_strategy_after_structure_rejection(&intervention)
    shape_runtime_for_strategy(&intervention.runtime_plan, intervention.strategy, achieved_target)
    scale_meters := clamp(
        intervention.runtime_plan.diagnostics.footprint_diameter,
        MIN_DIAMETER_METERS,
        MAX_DIAMETER_METERS,
    )
    build_routes(&intervention.runtime_plan, project, site, scale_meters)
    shape_terrain_edits_for_strategy(project, &intervention)
    intervention.achieved_capacity = intervention.runtime_plan.berth_count
    terrain_cost := f32(0)
    if intervention.terrain_area_limit > 0 {
        terrain_cost = intervention.terrain_edit_area / intervention.terrain_area_limit * .12
    }
    strategy_estimate := estimate_strategy(site, program, intervention.strategy)
    intervention.construction_cost = strategy_estimate.cost * .88 + terrain_cost
    shore := shoreline_sample(site, .34)
    landward := scale(shoreline_outward(site, .34), -1)
    append_waterfront_zone(&intervention, .Landing, shore, landward, 18, 10)
    append_waterfront_zone(&intervention, .Harbor_Office, intervention.runtime_plan.office, landward, 12, 10)
    if program.purpose == .Fishing || program.purpose == .Working_Port {
        append_waterfront_zone(&intervention, .Fish_Market, add(shore, scale(site.tangent, -24)), landward, 26, 15)
        append_waterfront_zone(&intervention, .Repair_Yard, add(shore, scale(site.tangent, 30)), landward, 34, 22)
    }
    if program.purpose == .Ferry {
        append_waterfront_zone(&intervention, .Ferry_Access, add(shore, scale(site.tangent, 26)), landward, 24, 18)
    }
    build_intervention_history(&intervention)
    intervention.runtime_plan.diagnostics = validate_intervention(project, &intervention)
    intervention.runtime_plan.valid = intervention.runtime_plan.diagnostics.valid
    intervention.valid = intervention.runtime_plan.valid
    return intervention
}

generate_for_survey :: proc(
    project: ^terrain.Project,
    survey: ^Coastal_Survey,
    program: ^Harbor_Program,
    seed: u32,
) -> Harbor_Intervention {
    best: Harbor_Intervention
    if project == nil || survey == nil || program == nil do return best
    ranked: [COASTAL_SITE_CAPACITY]Harbor_Site
    ranked_count := 0
    for source in survey.sites[:survey.site_count] {
        single: Coastal_Survey
        single.sites[0] = source
        single.site_count = 1
        scored := select_harbor_site(project, &single, program, seed ~ u32(ranked_count) * 0x9e37_79b9)
        if !scored.valid do continue
        insert_at := ranked_count
        for index in 0 ..< ranked_count {
            if scored.selection_score > ranked[index].selection_score {
                insert_at = index
                break
            }
        }
        if ranked_count < len(ranked) do ranked_count += 1
        for index := ranked_count - 1; index > insert_at; index -= 1 {
            ranked[index] = ranked[index - 1]
        }
        if insert_at < len(ranked) do ranked[insert_at] = scored
    }

    best_score := f32(-1000)
    for &site, trial_index in ranked[:min(ranked_count, SITE_TRIAL_CAPACITY)] {
        intervention := generate_intervention(project, &site, program, seed)
        if !intervention.valid do continue
        score :=
            site.selection_score +
            intervention.runtime_plan.diagnostics.naturalism_score * .12 +
            intervention.runtime_plan.diagnostics.navigation_score * .12 -
            intervention.construction_cost * .10 -
            f32(trial_index) * .002
        if !best.valid || score > best_score {
            best = intervention
            best_score = score
        }
    }
    return best
}

finalize_intervention :: proc(intervention: ^Harbor_Intervention) -> Harbor_Plan {
    if intervention == nil do return {}
    return intervention.runtime_plan
}

apply_harbor_terrain :: proc(project: ^terrain.Project, intervention: ^Harbor_Intervention) {
    if project == nil || intervention == nil || !intervention.valid do return
    apply_terrain_edits(project, &intervention.runtime_plan)
}
