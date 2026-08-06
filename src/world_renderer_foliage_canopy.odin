package main
import "core:math"

import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_foliage_lobe :: proc(
    structure: terrain.Structure,
    local_center_x, local_center_z, width, depth, height: f32,
    base_lift: f32,
    is_hedge: bool,
    variation: int,
    outline_angle: f32,
    emit_outline: bool,
    lod: Structure_LOD = .Near,
    orientation_offset: f32 = 0,
    opacity: f32 = 1,
    color_override: canvas2d.Color = {},
) {
    first_vertex := len(world_renderer.vertices)
    defer {
        resolved_opacity := clamp(opacity, f32(0), f32(1))
        for &vertex in world_renderer.vertices[first_vertex:] {
            vertex.color[3] *= resolved_opacity
            if color_override.a > 0 {
                source_value := (vertex.color[0] + vertex.color[1] + vertex.color[2]) / 3
                shade := clamp(source_value / .38, f32(.62), f32(1.32))
                vertex.color[0] = f32(color_override.r) / 255 * shade
                vertex.color[1] = f32(color_override.g) / 255 * shade
                vertex.color[2] = f32(color_override.b) / 255 * shade
            }
        }
    }
    // Smooth normals cannot repair a faceted outer contour. Eighteen sides
    // keep the long crown ridge and hanging skirt from resolving into obvious
    // straight runs at eye level. The deterministic radius and height rhythm
    // still does the silhouette design; the extra sides only let that rhythm
    // describe a soft painted edge.
    // Nearby crowns receive a finer silhouette while distant forest masses
    // retain the cheaper contour. This spends vertices where scallops occupy
    // multiple pixels instead of increasing every canopy in overview scenes.
    MAX_SEGMENTS :: 30
    segment_count := lod == .Near ? 30 : lod == .Medium ? 18 : 8
    lobe_world_x, lobe_world_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_center_x,
        local_center_z,
        structure.rotation,
    )
    PROFILE_RINGS :: 7
    MAX_RINGS :: 10
    ring_count := lod == .Near ? MAX_RINGS : lod == .Medium ? PROFILE_RINGS : 4
    if is_hedge {
        // Hedgerows can span an entire property edge. Keep their continuous
        // silhouette cheap: the overlapping crown beats hide the coarser
        // radial profile, so tree-quality tessellation buys little on screen.
        segment_count = lod == .Near ? 14 : lod == .Medium ? 10 : 8
        ring_count = lod == .Near ? 6 : lod == .Medium ? 5 : 4
    }
    // Elevated lobes are the crowns emitted by both mature forests and the
    // aerial-only young-woodland treatment. Use that semantic signal instead
    // of the parent footprint threshold so both share the same cheap tiers.
    is_forest_lobe := !is_hedge && base_lift > 0
    if is_forest_lobe && lod == .Medium {
        // At Medium range the crown occupies enough pixels to need a soft
        // scallop, but not the full near profile. Sixteen sides and six rings
        // retain the broad painted planes while cutting roughly one quarter
        // of per-crown topology from the tier that dominates stress scenes.
        segment_count = 16
        ring_count = 6
    }
    if is_forest_lobe && lod == .Far {
        // Dense stands contain dozens of tree-scale crowns. Eight sides and
        // four sampled profile rings are enough once those crowns merge into
        // a distant forest silhouette, while keeping the aggregate affordable.
        segment_count = 8
        ring_count = 4
    }
    // Near crowns keep the full medium and fine clump breakup; distant masses
    // shed it so their silhouette stays a calm, inexpensive composition of the
    // bold dominant bunches. The fade is continuous, so a crown morphs its
    // surface detail smoothly rather than popping at an LOD band boundary.
    clump_detail_fade := lod == .Near ? f32(1) : lod == .Medium ? f32(.45) : f32(0)
    // Canopy lobes are broad layered shelves, not inflated spheres. The
    // widest contour sits low, the upper shoulder stays full, and the shallow
    // cap produces a painted crown plane instead of a pointed balloon.
    ring_height := [PROFILE_RINGS]f32{.06, .15, .28, .43, .58, .71, .81}
    ring_radius := [PROFILE_RINGS]f32{.70, .86, .98, 1.0, .92, .69, .44}
    profile_width, profile_depth, profile_height := width, depth, height
    irregularity_strength := f32(.14)
    crown_base := f32(.90)
    species := int(structure.seed % 3)
    switch species {
    case 1:
        // Oak-like: a low, broad, rugged shelf with a full upper shoulder.
        ring_height = {.05, .14, .26, .39, .52, .64, .75}
        ring_radius = {.74, .88, .98, 1.0, .94, .74, .54}
        profile_width *= 1.09
        profile_depth *= 1.05
        profile_height *= .90
        irregularity_strength = .20
        crown_base = .85
    case 2:
        // Laurel-like: tighter upright bunches with a steeper shoulder and
        // smaller crown plane, useful as vertical accents in a mixed forest.
        ring_height = {.07, .18, .32, .47, .63, .77, .86}
        ring_radius = {.62, .82, .97, 1.0, .79, .52, .30}
        profile_width *= .84
        profile_depth *= .87
        profile_height *= 1.12
        irregularity_strength = .105
        crown_base = .96
    case:
    // Rounded broadleaf is the balanced default.
    }
    if base_lift > 0 {
        // Forest crowns join into broad, overlapping bough shelves. Keeping
        // their widest contour high and flattening the crown prevents a grove
        // from becoming a collection of upright gumdrops, while the stronger
        // irregularity preserves distinct hand-painted crown gestures.
        ring_height = {.04, .11, .21, .33, .46, .58, .69}
        ring_radius = {.78, .90, .98, 1.0, .94, .78, .58}
        profile_width *= 1.17
        profile_depth *= 1.10
        profile_height *= lod == .Near ? f32(.96) : lod == .Medium ? f32(.86) : f32(.79)
        // Forest crowns need decisive large clumps at both walking and aerial
        // scale. Subtle deformation leaves every tree as a separate circle;
        // stronger broad scallops interlock into a painted canopy edge.
        irregularity_strength = max(irregularity_strength, f32(.26))
        crown_base = .80
        switch species {
        case 1:
            // Mature oak shelves stay especially broad and low, with a full
            // shoulder and a gently recessed crown plane.
            ring_height = {.03, .09, .17, .28, .40, .52, .64}
            ring_radius = {.82, .93, .99, 1.0, .95, .79, .57}
            crown_base = .75
        case 2:
            // Laurel-like emergents keep a rising outer gesture, but retain a
            // full upper shoulder. A narrow final ring feeding a high point
            // made every accent read as a bright conical gumdrop.
            ring_height = {.05, .14, .25, .39, .53, .65, .74}
            ring_radius = {.70, .87, .98, 1.0, .91, .73, .56}
            profile_width *= 1.10
            profile_depth *= 1.08
            profile_height *= .90
            crown_base = .79
        case:
        // Balanced broadleaf keeps the shared forest shelf.
        }
    } else if is_hedge {
        // A maintained hedge is one shallow rolling volume rather than a row
        // of miniature trees. Preserve soft crown undulation while keeping
        // the shoulders broad enough for neighboring lobes to disappear into.
        ring_height = {.04, .10, .19, .31, .43, .55, .66}
        ring_radius = {.80, .91, .98, 1.0, .94, .79, .58}
        profile_width *= 1.08
        profile_depth *= 1.04
        profile_height *= .78
        irregularity_strength = max(irregularity_strength, f32(.15))
        crown_base = .76
    }
    // The seven authored profile points remain the shape authority. Nearby
    // crowns interpolate two additional contours from that same curve instead
    // of changing species proportions or procedural phases with LOD.
    sampled_ring_height: [MAX_RINGS]f32
    sampled_ring_radius: [MAX_RINGS]f32
    for ring in 0 ..< ring_count {
        profile_position := f32(ring) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1))
        lower := clamp(int(profile_position), 0, PROFILE_RINGS - 1)
        upper := min(lower + 1, PROFILE_RINGS - 1)
        fraction := profile_position - f32(lower)
        sampled_ring_height[ring] = ring_height[lower] + (ring_height[upper] - ring_height[lower]) * fraction
        sampled_ring_radius[ring] = ring_radius[lower] + (ring_radius[upper] - ring_radius[lower]) * fraction
    }
    vertices: [MAX_RINGS][MAX_SEGMENTS]third_person.Vec3
    normals: [MAX_RINGS][MAX_SEGMENTS]third_person.Vec3
    // Grounded foliage bends as one continuous blob over the terrain. Sample
    // each angular column once and reuse that offset through every profile
    // ring, keeping terrain queries proportional to the existing silhouette
    // resolution rather than the full vertex count.
    terrain_offsets: [MAX_SEGMENTS]f32
    // The signed clump field, sampled once per contour vertex, drives both the
    // rounded three-dimensional bulges and the crevice ambient occlusion baked
    // into the vertex colors, so the painted shade tracks the real mesh volume.
    clump_field: [MAX_RINGS][MAX_SEGMENTS]f32
    // One authored mass keeps a coherent species hue. Earlier per-lobe palette
    // cycling made close trees read as a patchwork of unrelated teal, olive,
    // and yellow polygons; lighting and brush marks already provide the
    // necessary internal variation.
    color_variation := int(structure.seed % 6)
    if is_hedge {
        // Clipped hedges alternate between deep cypress/myrtle and laurel.
        // They remain saturated enough to frame pale roads and stucco, while
        // avoiding the silver and hot olive families used by open scrub.
        hedge_palettes := [3]int{0, 3, 0}
        color_variation = hedge_palettes[int(structure.seed % 3)]
    }
    if base_lift > 0 {
        // Mature woods need broad color regions, not a checkerboard of random
        // lime and teal crowns. Sample the slow world-space field at this
        // crown, not at the center of its authored parent formation: otherwise
        // every tree in one patch receives the same palette and the patch
        // boundary becomes a conspicuous rectangular color seam from the air.
        // Crown-space sampling lets neighboring formations share continuous
        // painted regions while still drifting from cool recesses through
        // green into warm olive crowns. The hottest yellow-green family
        // remains available to standalone flowering bushes; across a mature
        // canopy it overexposes broad aerial faces and makes separate crowns
        // read as luminous shrubs instead of one deep woodland mass. Route
        // the warmest forest region to the quieter Mediterranean scrub family
        // so the upper rings stay sun-warmed without losing green shoulders.
        palette_field :=
            f32(math.sin(f64(lobe_world_x * .0092 + lobe_world_z * .0049))) +
            f32(math.sin(f64(lobe_world_x * -.0037 + lobe_world_z * .0081 + 1.7))) * .62
        if palette_field < -.76 {
            color_variation = 0
        } else if palette_field < -.10 {
            color_variation = 3
        } else if palette_field < .14 {
            color_variation = 4
        } else if palette_field < .78 {
            // Keep mature woodland in the cooler myrtle/silver-olive range.
            // The vivid laurel family is useful for isolated shrubs, but a
            // whole aerial region of it reads as fluorescent turf.
            color_variation = 3
        } else {
            color_variation = 3
        }
    }

    for ring in 0 ..< ring_count {
        profile_ring := f32(ring) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1))
        for segment in 0 ..< segment_count {
            // Slightly twist each contour so the facets do not stack into
            // continuous vertical seams. A deterministic phase keeps adjacent
            // lobes from sharing the same outline.
            contour_angle := f32(segment) * math.PI * 2 / f32(segment_count)
            angle :=
                contour_angle +
                profile_ring * .075 +
                f32(math.sin(f64(f32(variation) * 1.37 + profile_ring * 2.11))) * .045 +
                orientation_offset
            // Three correlated octaves compose the crown as bold, rounded
            // cumulus clumps with a clear big/medium/small nesting -- the
            // Ghibli canopy read -- rather than one uniform scallop frequency.
            // The dominant octave carves a few large bunches; the medium and
            // fine octaves only break their edges, and both quieter octaves
            // fade with distance so far masses stay calm while near crowns gain
            // hand-painted volume without changing topology or vertex cost.
            clump_dominant := f32(
                math.sin(
                    f64(f32(structure.seed) * .008 + f32(variation) * 1.63 + contour_angle * 1.8 + profile_ring * .42),
                ),
            )
            clump_medium := f32(
                math.sin(
                    f64(f32(structure.seed) * .013 + f32(variation) * 2.11 + contour_angle * 3.9 - profile_ring * .63),
                ),
            )
            clump_fine := f32(
                math.sin(
                    f64(f32(structure.seed) * .021 + f32(variation) * 2.67 + contour_angle * 7.1 + profile_ring * .94),
                ),
            )
            clump :=
                clump_dominant * .60 +
                clump_medium * .28 * (.5 + .5 * clump_detail_fade) +
                clump_fine * .14 * clump_detail_fade
            clump_field[ring][segment] = clump
            irregularity := 1 + clump * irregularity_strength
            local_x := local_center_x + math.cos(angle) * profile_width * .5 * sampled_ring_radius[ring] * irregularity
            local_z := local_center_z + math.sin(angle) * profile_depth * .5 * sampled_ring_radius[ring] * irregularity
            world_x, world_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            contour_lift :=
                f32(math.sin(f64(f32(structure.seed) * .007 + f32(variation) * 1.43 + contour_angle * 4.899))) *
                profile_height *
                (ring == 0 ? f32(.008) : f32(.026))
            // Bulge crests dome outward and upward while troughs carve soft
            // crevices, turning the wavy outline into rounded three-dimensional
            // bunches. The dome weight peaks on the mid and upper shoulder and
            // vanishes at the skirt so the hanging underside stays a clean
            // shelf rather than a rippled ceiling.
            dome_weight := sampled_ring_height[ring] * (1 - sampled_ring_height[ring]) * 4
            contour_lift += clump * profile_height * dome_weight * .055
            if base_lift > 0 && ring == 0 {
                // The lowest forest contour carries uneven hanging bough
                // pockets. A broad rhythm chooses the limbs while a smaller
                // ripple keeps their tips leafy, breaking the tabletop
                // underside without adding cards hidden inside the mesh.
                broad_droop := f32(
                    math.sin(f64(f32(structure.seed) * .017 + f32(variation) * 1.23 + contour_angle * 3.841)),
                )
                tip_droop := f32(
                    math.sin(f64(f32(structure.seed) * .029 + f32(variation) * 2.07 + contour_angle * 7.369 + .8)),
                )
                droop_wave := clamp(.5 + broad_droop * .34 + tip_droop * .16, 0, 1)
                contour_lift -= profile_height * (.010 + droop_wave * .068)
            }
            if base_lift <= 0 {
                if ring == 0 {
                    terrain_offsets[segment] =
                        terrain.sample_surface_height(&world_renderer.editor.project, 0, world_x, world_z) -
                        structure.base_y
                }
                contour_lift += terrain_offsets[segment]
            }
            vertices[ring][segment] = {
                world_x,
                structure.base_y + base_lift + profile_height * sampled_ring_height[ring] + contour_lift,
                world_z,
            }
            local_normal_x := math.cos(angle) * profile_height / max(profile_width, f32(.01))
            local_normal_y := (sampled_ring_height[ring] - .30) * 1.68
            local_normal_z := math.sin(angle) * profile_height / max(profile_depth, f32(.01))
            if base_lift > 0 {
                // Nearby forest lobes should share the lighting flow of their
                // parent crown. Blend each small ellipsoid normal toward a
                // broad formation normal so overlaps read as leafy bunches,
                // not colliding independently lit balls.
                mass_normal_x := local_x * structure.height * 2 / max(structure.width * structure.width, f32(.01))
                mass_normal_z := local_z * structure.height * 2 / max(structure.depth * structure.depth, f32(.01))
                local_normal_x += (mass_normal_x - local_normal_x) * .46
                local_normal_z += (mass_normal_z - local_normal_z) * .46
            }
            cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
            normals[ring][segment] = linalg.normalize0(
                third_person.Vec3 {
                    local_normal_x * cosine - local_normal_z * sine,
                    local_normal_y,
                    local_normal_x * sine + local_normal_z * cosine,
                },
            )
        }
    }

    base_x, base_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_center_x,
        local_center_z,
        structure.rotation,
    )
    base_fraction := f32(.065)
    if base_lift > 0 {
        // Lift the middle of an elevated crown's underside into a pronounced
        // concave bough pocket. The former shallow fan still read as a broad
        // dark ceiling at character height; this steeper closure reveals the
        // supporting fork while preserving the leafy hanging perimeter.
        base_fraction = .24
    }
    base_terrain_offset := f32(0)
    if base_lift <= 0 {
        base_terrain_offset =
            terrain.sample_surface_height(&world_renderer.editor.project, 0, base_x, base_z) - structure.base_y
    }
    base := third_person.Vec3 {
        base_x,
        structure.base_y + base_lift + profile_height * base_fraction + base_terrain_offset,
        base_z,
    }
    for segment in 0 ..< segment_count {
        next := (segment + 1) % segment_count
        if base_lift > 0 {
            world_triangle_foliage(
                vertices[0][next],
                base,
                vertices[0][segment],
                world_foliage_clump_color(0, color_variation, clump_field[0][next]),
                {39, 66, 48, 255},
                world_foliage_clump_color(0, color_variation, clump_field[0][segment]),
                normals[0][next],
                {0, -1, 0},
                normals[0][segment],
            )
        } else {
            world_triangle(vertices[0][next], base, vertices[0][segment], {34, 61, 45, 255})
        }
    }

    for ring in 0 ..< ring_count - 1 {
        lower_palette_ring := clamp(
            int(f32(ring) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1)) + .5),
            0,
            PROFILE_RINGS - 1,
        )
        upper_palette_ring := clamp(
            int(f32(ring + 1) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1)) + .5),
            0,
            PROFILE_RINGS - 1,
        )
        for segment in 0 ..< segment_count {
            next := (segment + 1) % segment_count
            // Paint soft ambient occlusion into the troughs between clumps and
            // a restrained warm lift onto their crests, per contour vertex, so
            // the grouped shade is anchored to the real mesh bulges instead of
            // a detached noise field. This is the crevice read that gives the
            // near canopy its rounded, hand-painted volume.
            lower_here := world_foliage_clump_color(lower_palette_ring, color_variation, clump_field[ring][segment])
            lower_next := world_foliage_clump_color(lower_palette_ring, color_variation, clump_field[ring][next])
            upper_here := world_foliage_clump_color(
                upper_palette_ring,
                color_variation,
                clump_field[ring + 1][segment],
            )
            upper_next := world_foliage_clump_color(upper_palette_ring, color_variation, clump_field[ring + 1][next])
            world_triangle_foliage(
                vertices[ring][segment],
                vertices[ring + 1][segment],
                vertices[ring + 1][next],
                lower_here,
                upper_here,
                upper_next,
                normals[ring][segment],
                normals[ring + 1][segment],
                normals[ring + 1][next],
            )
            world_triangle_foliage(
                vertices[ring][segment],
                vertices[ring + 1][next],
                vertices[ring][next],
                lower_here,
                upper_next,
                lower_next,
                normals[ring][segment],
                normals[ring + 1][next],
                normals[ring][next],
            )
        }
    }

    crown_x, crown_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_center_x + profile_width * f32(math.sin(f64(f32(variation) * 2.3))) * .035,
        local_center_z + profile_depth * f32(math.cos(f64(f32(variation) * 1.7))) * .035,
        structure.rotation,
    )
    crown_fraction := crown_base + f32(math.sin(f64(f32(structure.seed) * .005 + f32(variation) * 1.61))) * .035
    crown_terrain_offset := f32(0)
    if base_lift <= 0 {
        crown_terrain_offset =
            terrain.sample_surface_height(&world_renderer.editor.project, 0, crown_x, crown_z) - structure.base_y
    }
    crown := third_person.Vec3 {
        crown_x,
        structure.base_y + base_lift + profile_height * crown_fraction + crown_terrain_offset,
        crown_z,
    }
    for segment in 0 ..< segment_count {
        next := (segment + 1) % segment_count
        world_triangle_foliage(
            vertices[ring_count - 1][segment],
            crown,
            vertices[ring_count - 1][next],
            world_foliage_clump_color(PROFILE_RINGS - 1, color_variation, clump_field[ring_count - 1][segment]),
            world_foliage_vertex_color(PROFILE_RINGS - 1, color_variation),
            world_foliage_clump_color(PROFILE_RINGS - 1, color_variation, clump_field[ring_count - 1][next]),
            normals[ring_count - 1][segment],
            {0, 1, 0},
            normals[ring_count - 1][next],
        )
    }

    // The atlas is primarily a silhouette accent. Perimeter boughs carry the
    // large sprays; clipped hedges also receive a few much smaller translucent
    // face clusters below so their long front plane does not stay textureless.
    if emit_outline && lod != .Far {
        // Intersect the requested outward ray with the independently rotated
        // crown ellipse. Using the old unrotated width/depth parameterization
        // left sprays inside or outside anisotropic crowns after per-tree
        // orientation was introduced.
        relative_angle := outline_angle - orientation_offset
        relative_x, relative_z := math.cos(relative_angle), math.sin(relative_angle)
        safe_width, safe_depth := max(profile_width, f32(.01)), max(profile_depth, f32(.01))
        ray_scale :=
            .64 /
            max(
                f32(
                    math.sqrt(
                        f64(
                            relative_x * relative_x / (safe_width * safe_width) +
                            relative_z * relative_z / (safe_depth * safe_depth),
                        ),
                    ),
                ),
                f32(.001),
            )
        local_x := local_center_x + math.cos(outline_angle) * ray_scale
        local_z := local_center_z + math.sin(outline_angle) * ray_scale
        card_x, card_z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
        focal_length := f32(1.35)
        if world_renderer.editor.in_map && driving_aircraft(world_renderer.editor) {
            focal_length = world_renderer.editor.flight_camera.focal_length
        }
        camera := perspective_camera(world_renderer.editor.camera_pose, focal_length)
        to_camera_x := camera.position.x - card_x
        to_camera_z := camera.position.z - card_z
        to_camera_length := max(f32(.001), f32(math.sqrt(f64(to_camera_x * to_camera_x + to_camera_z * to_camera_z))))
        // Ellipse surface normals are not generally radial. Transform the
        // local gradient back through the crown rotation so side-on admission
        // and echo offsets follow the actual oriented crown shoulder.
        normal_local_x := relative_x / (safe_width * safe_width)
        normal_local_z := relative_z / (safe_depth * safe_depth)
        orientation_cos, orientation_sin := math.cos(orientation_offset), math.sin(orientation_offset)
        normal_x := normal_local_x * orientation_cos - normal_local_z * orientation_sin
        normal_z := normal_local_x * orientation_sin + normal_local_z * orientation_cos
        outward_angle := math.atan2(normal_z, normal_x) + structure.rotation
        view_alignment := math.abs(
            math.cos(outward_angle) * to_camera_x / to_camera_length +
            math.sin(outward_angle) * to_camera_z / to_camera_length,
        )

        // Only side-on perimeter boughs break the screen-space silhouette.
        // Front-facing billboards would lie across the crown and read as giant
        // flat polygons when the camera approaches tree height. The near band
        // is now admitted -- down to a few crown radii away -- so walking-height
        // and understory views gain a soft leafy contour instead of the bare
        // triangulated mesh edge. It stays side-on and is eased in very small,
        // so the sprig sits on the silhouette rather than sheeting across it,
        // and because only nearby lobes qualify the card budget stays bounded
        // (overview forest and stress scenes keep the existing far-only path).
        if view_alignment < .68 && to_camera_length > 34 {
            card_scale_factor := f32(.255 + f32(variation % 3) * .018)
            if is_hedge do card_scale_factor = .225 + f32(variation % 3) * .016
            if !is_hedge && base_lift <= 0 {
                card_scale_factor = .292 + f32(variation % 3) * .018
            }
            // Cards ease in small near the camera as leafy contour nicks, reach
            // full silhouette-breaking size by mid distance, and hold there.
            near_mix := clamp((to_camera_length - 34) / 78, 0, 1)
            far_mix := clamp((to_camera_length - 112) / 82, 0, 1)
            distance_scale := .52 + near_mix * .24 + far_mix * .24
            card_scale := card_scale_factor * max(profile_width, profile_depth)
            card_scale *= distance_scale
            card_y := structure.base_y + base_lift + profile_height * (.51 + f32(variation % 3) * .032)
            world_foliage_card(
                {card_x, card_y, card_z},
                card_scale,
                card_scale * .82,
                variation * 5 + 7,
                world_foliage_vertex_color(3, color_variation),
                (variation + int(structure.seed)) % 2 == 0,
            )

            // A smaller offset spray turns the single cutout into an uneven
            // leafy bunch. Offset both outward and along the contour so the
            // pair overlaps near its branch bases but separates at the tips,
            // breaking the parent mesh silhouette at two different scales.
            tangent_x, tangent_z := -math.sin(outward_angle), math.cos(outward_angle)
            echo_side := (variation + int(structure.seed)) % 2 == 0 ? f32(1) : f32(-1)
            echo_x := card_x + math.cos(outward_angle) * card_scale * .10 + tangent_x * card_scale * .17 * echo_side
            echo_z := card_z + math.sin(outward_angle) * card_scale * .10 + tangent_z * card_scale * .17 * echo_side
            echo_scale := card_scale * (.63 + f32(variation % 2) * .055)
            world_foliage_card(
                {echo_x, card_y + card_scale * (.09 + f32(variation % 3) * .018), echo_z},
                echo_scale,
                echo_scale * .88,
                variation * 7 + 3,
                world_foliage_vertex_color(2, color_variation + 1),
                (variation + int(structure.seed)) % 2 != 0,
            )

            // Alternating mature-forest boughs receive one inverted lower
            // spray. Its branch base stays buried in the dark shelf while the
            // painted tips trail below, breaking the long canopy-ceiling edge
            // without filling the open understory with billboard cards.
            hanging_selected := base_lift > 0 && to_camera_length > 76
            if hanging_selected {
                hanging_scale := card_scale * (.57 + f32(variation % 3) * .028)
                hanging_side := variation % 2 == 0 ? f32(1) : f32(-1)
                hanging_x :=
                    card_x + math.cos(outward_angle) * card_scale * .055 + tangent_x * card_scale * .11 * hanging_side
                hanging_z :=
                    card_z + math.sin(outward_angle) * card_scale * .055 + tangent_z * card_scale * .11 * hanging_side
                world_foliage_card(
                    {
                        hanging_x,
                        structure.base_y + base_lift + profile_height * (.175 + f32(variation % 2) * .026),
                        hanging_z,
                    },
                    hanging_scale,
                    hanging_scale * 1.18,
                    variation * 11 + 5,
                    world_foliage_vertex_color(2, color_variation),
                    hanging_side < 0,
                    true,
                )
            }
        }

        hedge_face_selected :=
            is_hedge && to_camera_length > 72 && to_camera_length < 430 && (variation + int(structure.seed)) % 2 == 0
        if hedge_face_selected {
            // Push the accent onto the camera-facing shoulder so depth testing
            // attaches it to the solid crown instead of hiding it inside the
            // lobe. Partial opacity and alternating placement keep these as
            // broken leaf suggestions rather than a repeated decal strip.
            face_offset := min(profile_width, profile_depth) * .47
            face_x := lobe_world_x + to_camera_x / to_camera_length * face_offset
            face_z := lobe_world_z + to_camera_z / to_camera_length * face_offset
            face_scale := min(profile_width, profile_depth) * (.235 + f32(variation % 3) * .016)
            face_tint := world_foliage_vertex_color(3, color_variation)
            face_tint.a = 198
            world_foliage_card(
                {face_x, structure.base_y + profile_height * (.49 + f32(variation % 3) * .045), face_z},
                face_scale,
                face_scale * .78,
                variation * 13 + 9,
                face_tint,
                (variation + int(structure.seed)) % 4 == 0,
            )
        }

        bush_face_selected :=
            !is_hedge &&
            base_lift <= 0 &&
            to_camera_length > 78 &&
            to_camera_length < 430 &&
            (variation + int(structure.seed)) % 3 != 0
        if bush_face_selected {
            // Standalone bushes can carry a little more leaf-scale surface
            // rhythm than distant forest masses. Keep the accents small and
            // translucent so several read as one painted bunch, not stickers.
            face_offset := min(profile_width, profile_depth) * .46
            face_x := lobe_world_x + to_camera_x / to_camera_length * face_offset
            face_z := lobe_world_z + to_camera_z / to_camera_length * face_offset
            face_scale := min(profile_width, profile_depth) * (.19 + f32(variation % 3) * .014)
            face_tint := world_foliage_vertex_color(3, color_variation)
            face_tint.a = 186
            world_foliage_card(
                {face_x, structure.base_y + profile_height * (.50 + f32(variation % 3) * .042), face_z},
                face_scale,
                face_scale * .84,
                variation * 17 + 1,
                face_tint,
                (variation + int(structure.seed)) % 2 == 0,
            )
        }
    }
}
