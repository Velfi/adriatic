package main
import "core:math"

import flight "../packages/flight"
import plants "../packages/plants"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import canvas2d "zelda_engine:canvas2d"

world_character :: proc(editor: ^Editor) {
    if !editor.in_map || editor.pilot.mode != .On_Foot do return
    if !world_sphere_in_view(editor, editor.player.position + third_person.Vec3{0, .8, 0}, 2, 5) do return
    world_mouse_model(
        editor,
        {
            position = editor.player.position,
            rotation = math.PI - editor.player.facing_yaw_radians,
            accessory = editor.mouse_headgear,
            fur = editor.mouse_fur,
            pattern = editor.mouse_pattern,
            scarf_enabled = editor.mouse_scarf_enabled,
            scarf_color = editor.mouse_scarf_color,
            mailbag_enabled = !editor.capture_player_mailbag_hidden,
            player_controlled = true,
            track_paw_plants = true,
            grounded = editor.player.grounded,
        },
    )
}

world_postale_pilot :: proc(editor: ^Editor) {
    if !editor.in_map || !editor.postale_visible || editor.pilot.mode != .Driving do return
    if editor.pilot.vehicle != &editor.postale.vehicle do return

    body := editor.postale.body
    basis := flight.basis_from_orientation(body.orientation)
    // Parent the pilot to a fixed seat in Postale mesh-local space. The mouse
    // model's origin is at its feet, so the seat belongs below the high wing,
    // inside the forward fuselage—not on top of the aircraft.
    seat_local := [3]f32{0, -.37, -.20}
    position := postale_vertex_world(&editor.postale, seat_local, POSTALE_PRESENTATION_SCALE)
    rotation := math.atan2(-basis.forward.x, -basis.forward.z)
    world_mouse_model_parented(
        editor,
        {
            position = position,
            rotation = rotation,
            accessory = editor.mouse_headgear,
            fur = editor.mouse_fur,
            pattern = editor.mouse_pattern,
            scarf_enabled = editor.mouse_scarf_enabled,
            scarf_color = editor.mouse_scarf_color,
            player_controlled = true,
            grounded = false,
            hide_tail = true,
            hide_hind_feet = true,
            driving_pose = true,
        },
        basis,
    )
}

MARTA_STOOL_HEIGHT :: f32(.49)

Business_Sign_Kind :: enum {
    Post,
    Fortuna,
    Clinica,
    Pane,
    Aerodromo,
}

world_business_sign_face :: proc(center: third_person.Vec3, rotation, width, height: f32, kind: Business_Sign_Kind) {
    outward := third_person.Vec3{-math.sin(rotation), 0, math.cos(rotation)}
    right := third_person.Vec3{math.cos(rotation), 0, math.sin(rotation)}
    tile_width := f32(1) / 5
    tile_u := f32(kind) * tile_width
    segments := 32
    for segment in 0 ..< segments {
        angle_0 := f32(segment) / f32(segments) * 2 * math.PI
        angle_1 := f32(segment + 1) / f32(segments) * 2 * math.PI
        local_0 := third_person.Vec3{math.cos(angle_0) * width * .48, math.sin(angle_0) * height * .43, 0}
        local_1 := third_person.Vec3{math.cos(angle_1) * width * .48, math.sin(angle_1) * height * .43, 0}
        points := [3]third_person.Vec3 {
            center,
            center + right * local_0.x + third_person.Vec3{0, local_0.y, 0},
            center + right * local_1.x + third_person.Vec3{0, local_1.y, 0},
        }
        uvs := [3][2]f32 {
            {tile_u + tile_width * .5, .5},
            {tile_u + (.5 + math.cos(angle_0) * .48) * tile_width, .5 - math.sin(angle_0) * .43},
            {tile_u + (.5 + math.cos(angle_1) * .48) * tile_width, .5 - math.sin(angle_1) * .43},
        }
        for vertex_index in 0 ..< 3 {
            vertex := world_vertex(points[vertex_index], {255, 255, 255, 255})
            vertex.kind = .Sign
            vertex.normal = {outward.x, outward.y, outward.z}
            vertex.uv = uvs[vertex_index]
            append(&world_renderer.vertices, vertex)
        }
    }
}

world_business_sign :: proc(center: third_person.Vec3, rotation: f32, kind: Business_Sign_Kind, width: f32 = 1.72) {
    height := width
    // These are enamel wall plaques, not projecting box signs. Keep enough
    // edge to catch a highlight without presenting a black slab from the side.
    depth := f32(.075)
    segments := 24
    outward := third_person.Vec3{-math.sin(rotation), 0, math.cos(rotation)}
    rim := canvas2d.Color{55, 49, 43, 255}
    backing := canvas2d.Color{83, 70, 56, 255}
    for segment in 0 ..< segments {
        angle_0 := f32(segment) / f32(segments) * 2 * math.PI
        angle_1 := f32(segment + 1) / f32(segments) * 2 * math.PI
        local_0 := third_person.Vec3{math.cos(angle_0) * width * .48, math.sin(angle_0) * height * .43, 0}
        local_1 := third_person.Vec3{math.cos(angle_1) * width * .48, math.sin(angle_1) * height * .43, 0}
        p0x, p0z := world_rotate_xz(center.x, center.z, local_0.x, 0, rotation)
        p1x, p1z := world_rotate_xz(center.x, center.z, local_1.x, 0, rotation)
        front_0 := third_person.Vec3{p0x, center.y + local_0.y, p0z} + outward * (depth * .5)
        front_1 := third_person.Vec3{p1x, center.y + local_1.y, p1z} + outward * (depth * .5)
        back_0 := front_0 - outward * depth
        back_1 := front_1 - outward * depth
        world_quad(front_0, back_0, back_1, front_1, rim)
        world_triangle(center + outward * depth * .5, front_0, front_1, backing)
        world_triangle(center - outward * depth * .5, back_1, back_0, backing)
    }
    world_business_sign_face(center + outward * (depth * .5 + .006), rotation, width, height, kind)
    // Two short concealed cleats tie the plaque directly to the façade. The
    // former overhead gallows floated above the artwork and made the assembly
    // read as several unrelated props when viewed edge-on.
    for side in -1 ..= 1 {
        if side == 0 do continue
        cleat_x, cleat_z := world_rotate_xz(center.x, center.z, f32(side) * width * .27, -.105, rotation)
        world_box_rotated({cleat_x, center.y + height * .25, cleat_z}, {.10, .16, .18}, rotation, rim)
    }
}

world_business_sign_for_resident :: proc(editor: ^Editor, resident: story.Resident, kind: Business_Sign_Kind) {
    position, rotation, found := world_story_resident_home_pose(editor, resident)
    if !found do return
    side := resident == .Lena || resident == .Anica ? f32(-1) : f32(1)
    // Home poses stand well clear of the doorway. Move the plaque back by
    // that same clearance so its rear face rests on the façade.
    frontage_clearance: f32
    switch resident {
    case .Niko:
        frontage_clearance = 2.5
    case .Zora:
        frontage_clearance = 2.6
    case .Vesna:
        frontage_clearance = 2.2
    case .Anica, .Toma, .Lena:
        frontage_clearance = 2.3
    case .Marta, .Gerta, .Iva, .Bojan, .Petar, .Mirna:
        frontage_clearance = 2.4
    }
    plaque_half_depth := f32(.075 * .5)
    x, z := world_rotate_xz(position.x, position.z, side * 1.45, -frontage_clearance + plaque_half_depth, rotation)
    world_business_sign({x, position.y + 2.44, z}, rotation, kind)
}

AIRPORT_ARCADE_CENTER_Z :: f32(5.8)

@(no_instrumentation)
airport_kiosk_geometry_cache_entry :: #force_inline proc(
    position: third_person.Vec3,
    rotation: f32,
) -> ^Airport_Kiosk_Geometry_Cache {
    for &entry in world_renderer.airport_kiosk_geometry_cache {
        if entry.position_x == position.x && entry.position_z == position.z && entry.rotation == rotation {
            return &entry
        }
    }
    append(&world_renderer.airport_kiosk_geometry_cache, Airport_Kiosk_Geometry_Cache{})
    entry := &world_renderer.airport_kiosk_geometry_cache[len(world_renderer.airport_kiosk_geometry_cache) - 1]
    entry.position_x = position.x
    entry.position_z = position.z
    entry.rotation = rotation
    return entry
}

airport_kiosk_plant_lods :: #force_inline proc(
    editor: ^Editor,
    position: third_person.Vec3,
    ground, rotation: f32,
) -> [4]Generated_Plant_Render_LOD {
    lods: [4]Generated_Plant_Render_LOD
    planter_offsets := [4][2]f32{{-11.45, 5.8}, {11.45, 5.8}, {-11.45, 11.35}, {11.45, 11.35}}
    for offset, planter_index in planter_offsets {
        planter_x, planter_z := world_rotate_xz(position.x, position.z, offset.x, offset.y, rotation)
        lods[planter_index] = generated_plant_render_lod(
            editor.camera_pose.position,
            {planter_x, ground + .96, planter_z},
        )
    }
    return lods
}

airport_service_position :: proc(anchor: third_person.Vec3) -> third_person.Vec3 {
    sign := anchor.x >= 0 ? f32(1) : f32(-1)
    rotation := sign > 0 ? -f32(math.PI) * .5 : f32(math.PI) * .5
    x, z := world_rotate_xz(anchor.x, anchor.z, 0, AIRPORT_ARCADE_CENTER_Z, rotation)
    return {x, anchor.y, z}
}

world_attendant_kiosk :: proc(editor: ^Editor) {
    if editor == nil do return
    if world_sphere_in_view(editor, editor.attendant_position + third_person.Vec3{0, 4, 0}, 24, 8) {
        world_attendant_kiosk_at(editor, editor.attendant_position)
    }
    if world_sphere_in_view(editor, editor.gerta_position + third_person.Vec3{0, 4, 0}, 24, 8) {
        world_attendant_kiosk_at(editor, editor.gerta_position)
    }
    for structure in editor.project.structures[:editor.project.structure_count] {
        if !airport_structure_is_stamp(structure) do continue
        position := third_person.Vec3{structure.center_x, structure.base_y, structure.center_z}
        if world_sphere_in_view(editor, position + third_person.Vec3{0, 4, 0}, 24, 8) {
            world_attendant_kiosk_at(editor, position, structure.rotation, true)
        }
    }
    if editor.airport_stamp_mode && editor.airport_preview_valid {
        position := third_person.Vec3 {
            editor.airport_preview_x,
            terrain.sample_surface_height(&editor.project, 0, editor.airport_preview_x, editor.airport_preview_z),
            editor.airport_preview_z,
        }
        world_attendant_kiosk_at(editor, position, editor.airport_stamp_yaw, true)
    }
}

world_attendant_kiosk_at :: proc(
    editor: ^Editor,
    p: third_person.Vec3,
    authored_rotation: f32 = 0,
    use_authored_rotation: bool = false,
) {
    ground := terrain.sample_surface_height(&editor.project, 0, p.x, p.z)
    sign := p.x >= 0 ? f32(1) : f32(-1)
    rotation := use_authored_rotation ? authored_rotation : (sign > 0 ? -f32(math.PI) * .5 : f32(math.PI) * .5)
    cache := airport_kiosk_geometry_cache_entry(p, rotation)
    plant_lods := airport_kiosk_plant_lods(editor, p, ground, rotation)
    windsock_x, windsock_z := world_rotate_xz(p.x, p.z, 16.8, 14.2, rotation)
    if cache.valid && cache.terrain_revision == editor.terrain_revision && cache.plant_lods == plant_lods {
        append(&world_renderer.vertices, ..cache.prefix_vertices[:])
        world_procedural_windsock(editor, {windsock_x, ground, windsock_z}, (p.x + p.z) * .017)
        append(&world_renderer.vertices, ..cache.suffix_vertices[:])
        return
    }
    first_vertex := len(world_renderer.vertices)
    // A broad forecourt meets the asphalt access-road node at reception.
    world_airport_land_surface_rotated(editor, p.x, p.z, 42, 30, rotation, .10, .Exterior_Forecourt_Paving)
    forecourt_x, forecourt_z := world_rotate_xz(p.x, p.z, 0, -17, rotation)
    world_airport_land_surface_rotated(editor, forecourt_x, forecourt_z, 15, 20, rotation, .11, .Airport_Asphalt)
    // Painted centerline and drainage hardware make the road/forecourt
    // transition legible and exercise the civil material family.
    world_airport_box_rotated(
        {forecourt_x, ground + .135, forecourt_z},
        {.16, .025, 13.0},
        rotation,
        .Road_Marking_Ochre,
    )
    for stripe in -2 ..= 2 {
        stripe_x, stripe_z := world_rotate_xz(forecourt_x, forecourt_z, 0, f32(stripe) * 2.5, rotation)
        world_airport_box_rotated({stripe_x, ground + .14, stripe_z}, {5.8, .018, .16}, rotation, .Road_Marking_White)
    }
    drain_x, drain_z := world_rotate_xz(forecourt_x, forecourt_z, 5.4, 0, rotation)
    world_airport_box_rotated({drain_x, ground + .145, drain_z}, {1.5, .035, .55}, rotation, .Drainage_Grate)
    curb_sides := [2]f32{-1, 1}
    for side in curb_sides {
        curb_x, curb_z := world_rotate_xz(forecourt_x, forecourt_z, side * 7.35, 0, rotation)
        world_airport_box_rotated({curb_x, ground + .20, curb_z}, {.30, .18, 19.5}, rotation, .Pale_Concrete_Curb)
    }

    // An open passenger arcade replaces the enclosed terminal. Paired piers
    // and high lintels define each bay while keeping clear views and walking
    // routes through the building from the forecourt to the airfield.
    arcade_x, arcade_z := world_rotate_xz(p.x, p.z, 0, AIRPORT_ARCADE_CENTER_Z, rotation)
    world_airport_land_surface_rotated(editor, arcade_x, arcade_z, 30, 18, rotation, .12, .Arcade_Terrazzo)
    world_airport_land_surface_rotated(editor, arcade_x, arcade_z, 5.2, 5.2, rotation, .135, .Foot_Polished_Terrazzo)
    arcade_sides := [2]f32{-1, 1}
    for side in arcade_sides {
        for bay in -3 ..= 3 {
            pier_x, pier_z := world_rotate_xz(p.x, p.z, f32(bay) * 4.25, 5.8 + side * 7.4, rotation)
            world_airport_box_rotated(
                {pier_x, ground + 2.35, pier_z},
                {.62, 4.7, .72},
                rotation,
                .Pale_Adriatic_Limestone,
            )
        }
        rail_x, rail_z := world_rotate_xz(p.x, p.z, 0, 5.8 + side * 7.4, rotation)
        world_airport_box_rotated({rail_x, ground + 4.48, rail_z}, {26.1, .48, .78}, rotation, .Sun_Washed_Stucco)
        world_airport_box_rotated({rail_x, ground + 4.80, rail_z}, {27.0, .18, 1.02}, rotation, .Aerodromo_Enamel_Rim)
    }

    // Broad end frames brace the arcade without closing it off.
    for end in arcade_sides {
        for side in arcade_sides {
            pier_x, pier_z := world_rotate_xz(p.x, p.z, end * 13.1, 5.8 + side * 7.4, rotation)
            world_airport_box_rotated(
                {pier_x, ground + 2.35, pier_z},
                {.72, 4.7, .72},
                rotation,
                .Exposed_Salted_Limestone,
            )
        }
        lintel_x, lintel_z := world_rotate_xz(p.x, p.z, end * 13.1, 5.8, rotation)
        world_airport_box_rotated(
            {lintel_x, ground + 4.48, lintel_z},
            {.78, .48, 15.5},
            rotation,
            .Pale_Adriatic_Limestone,
        )
    }
    world_airport_box_rotated({arcade_x, ground + 5.05, arcade_z}, {27.6, .24, 16.2}, rotation, .Standing_Seam_Roof)

    // A raised monitor admits light along the full concourse and gives the
    // low, open building an airport silhouette without a separate tower.
    world_airport_box_rotated({arcade_x, ground + 5.42, arcade_z}, {17.2, .66, 5.2}, rotation, .Monitor_Tinted_Glass)
    world_airport_box_rotated({arcade_x, ground + 5.42, arcade_z}, {17.5, .10, 5.5}, rotation, .Anodized_Glazing_Frame)
    world_airport_box_rotated({arcade_x, ground + 5.82, arcade_z}, {18.0, .18, 6.0}, rotation, .Standing_Seam_Roof)
    // Face the plaque toward the forecourt and seat it on the front arcade
    // beam. The former roofline placement exposed its dark rear edge from the
    // main approach and made the sign read as an unexplained cylinder.
    sign_x, sign_z := world_rotate_xz(p.x, p.z, 0, -1.98, rotation)
    world_business_sign({sign_x, ground + 4.50, sign_z}, rotation + math.PI, .Aerodromo, 1.75)

    // A real wind-reading instrument belongs on the open airfield side of
    // each terminal. Its six articulated bands follow the same authoritative
    // weather vector used by aircraft, foliage, clouds, and water.
    windsock_first := len(world_renderer.vertices)
    world_procedural_windsock(editor, {windsock_x, ground, windsock_z}, (p.x + p.z) * .017)
    windsock_end := len(world_renderer.vertices)

    // A circular check-in counter makes reception an island within the open
    // arcade rather than a second roofed building. Overlapping tangent facets
    // make the ring read continuously while preserving the attendant's
    // existing interaction point at its center.
    COUNTER_SEGMENTS :: 16
    counter_radius := f32(1.65)
    for segment in 0 ..< COUNTER_SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(COUNTER_SEGMENTS)
        local_x := math.cos(angle) * counter_radius
        local_z := AIRPORT_ARCADE_CENTER_Z + math.sin(angle) * counter_radius
        segment_x, segment_z := world_rotate_xz(p.x, p.z, local_x, local_z, rotation)
        tangent_rotation := rotation + angle + math.PI * .5
        world_airport_box_rotated(
            {segment_x, ground + .92, segment_z},
            {.76, 1.05, .58},
            tangent_rotation,
            .Teal_Counter_Tile,
        )
        if segment & 3 == 0 {
            world_airport_box_rotated(
                {segment_x, ground + .94, segment_z},
                {.025, .90, .595},
                tangent_rotation,
                .Counter_Grout,
            )
        }
        world_airport_box_rotated(
            {segment_x, ground + .41, segment_z},
            {.77, .12, .60},
            tangent_rotation,
            .Counter_Toe_Kick,
        )
        world_airport_box_rotated(
            {segment_x, ground + 1.48, segment_z},
            {.82, .10, .76},
            tangent_rotation,
            .Counter_Worktop_Laminate,
        )
    }

    // Arrange working pieces along the forecourt arc: ticket ledger, document
    // tray, service bell, and a compact inward-facing timetable screen.
    ledger_x, ledger_z := world_rotate_xz(p.x, p.z, -.82, AIRPORT_ARCADE_CENTER_Z - 1.44, rotation)
    world_airport_box_rotated({ledger_x, ground + 1.56, ledger_z}, {1.15, .06, .72}, rotation, .Painted_Steel)
    world_airport_box_rotated({ledger_x, ground + 1.595, ledger_z}, {.88, .018, .54}, rotation, .Aerodromo_Enamel_Face)
    tray_x, tray_z := world_rotate_xz(p.x, p.z, .18, AIRPORT_ARCADE_CENTER_Z - 1.62, rotation)
    world_airport_box_rotated({tray_x, ground + 1.59, tray_z}, {1.25, .14, .72}, rotation, .Aerodromo_Enamel_Rim)
    world_airport_box_rotated({tray_x, ground + 1.68, tray_z}, {1.05, .05, .52}, rotation, .Aerodromo_Enamel_Face)
    bell_x, bell_z := world_rotate_xz(p.x, p.z, 1.02, AIRPORT_ARCADE_CENTER_Z - 1.25, rotation)
    world_airport_box_rotated({bell_x, ground + 1.635, bell_z}, {.30, .035, .30}, rotation, .Aged_Brass_Details)
    world_vertical_prism({bell_x, ground + 1.63, bell_z}, .18, .18, .22, math.PI / 8, {203, 160, 63, 255})
    screen_x, screen_z := world_rotate_xz(p.x, p.z, -1.28, AIRPORT_ARCADE_CENTER_Z + .12, rotation)
    world_airport_box_rotated(
        {screen_x, ground + 1.92, screen_z},
        {1.05, .72, .16},
        rotation + math.PI * .5,
        .Dark_Hardware,
    )
    screen_face_x, screen_face_z := world_rotate_xz(p.x, p.z, -1.185, AIRPORT_ARCADE_CENTER_Z + .12, rotation)
    world_airport_box_rotated(
        {screen_face_x, ground + 1.92, screen_face_z},
        {.82, .48, .025},
        rotation + math.PI * .5,
        .Monitor_Tinted_Glass,
    )

    // A freestanding mechanical baggage scale completes the passenger side of
    // the counter. Its platform sits beside—not in front of—the service point.
    scale_local_x, scale_local_z := f32(3.15), AIRPORT_ARCADE_CENTER_Z - .30
    scale_x, scale_z := world_rotate_xz(p.x, p.z, scale_local_x, scale_local_z, rotation)
    world_airport_box_rotated({scale_x, ground + .18, scale_z}, {1.55, .18, 1.35}, rotation, .Painted_Steel)
    column_x, column_z := world_rotate_xz(p.x, p.z, scale_local_x, scale_local_z - .42, rotation)
    world_airport_box_rotated({column_x, ground + .92, column_z}, {.22, 1.45, .22}, rotation, .Dark_Hardware)
    world_airport_box_rotated({column_x, ground + 1.58, column_z}, {1.08, .78, .34}, rotation, .Painted_Steel)
    dial_x, dial_z := world_rotate_xz(p.x, p.z, scale_local_x, scale_local_z - .235, rotation)
    world_airport_box_rotated({dial_x, ground + 1.58, dial_z}, {.82, .54, .025}, rotation, .Aerodromo_Enamel_Face)
    needle_x, needle_z := world_rotate_xz(p.x, p.z, scale_local_x, scale_local_z - .225, rotation)
    world_airport_box_rotated({needle_x, ground + 1.56, needle_z}, {.055, .30, .030}, rotation, .Aerodromo_Enamel_Rim)

    // Waiting benches face the forecourt on either side of the kiosk. Their
    // flanking planters soften the long arcade without narrowing its central
    // route or blocking any of the open structural bays.
    for side in arcade_sides {
        bench_x, bench_z := world_rotate_xz(p.x, p.z, side * 8.25, 5.8, rotation)
        for slat in -2 ..= 2 {
            slat_z := f32(slat) * .16
            seat_x, seat_z := world_rotate_xz(bench_x, bench_z, 0, slat_z, rotation)
            world_airport_box_rotated(
                {seat_x, ground + .74, seat_z},
                {3.2, .11, .13},
                rotation,
                .Bench_Slatted_Hardwood,
            )
            back_x, back_z := world_rotate_xz(bench_x, bench_z, 0, .34, rotation)
            world_airport_box_rotated(
                {back_x, ground + 1.08 + f32(slat) * .14, back_z},
                {3.2, .11, .13},
                rotation,
                .Bench_Slatted_Hardwood,
            )
        }
        for leg_side in arcade_sides {
            leg_x, leg_z := world_rotate_xz(bench_x, bench_z, leg_side * 1.22, 0, rotation)
            world_airport_box_rotated({leg_x, ground + .43, leg_z}, {.12, .58, .52}, rotation, .Painted_Steel)
        }
    }
    planter_offsets := [4][2]f32{{-11.45, 5.8}, {11.45, 5.8}, {-11.45, 11.35}, {11.45, 11.35}}
    for offset, planter_index in planter_offsets {
        planter_x, planter_z := world_rotate_xz(p.x, p.z, offset.x, offset.y, rotation)
        planter_base := third_person.Vec3{planter_x, ground + .12, planter_z}
        world_airport_box_rotated(
            {planter_base.x, ground + .50, planter_base.z},
            {1.25, .76, 1.25},
            rotation,
            .Fired_Terracotta,
        )
        world_airport_box_rotated(
            {planter_base.x, ground + .90, planter_base.z},
            {1.02, .035, 1.02},
            rotation,
            .Moist_Planter_Soil,
        )
        _ = world_generated_plant(
            planter_index & 1 == 0 ? plants.Species.Oleander : plants.Species.Lavender,
            u64(0xa17c_ade0) ~ u64(planter_index) ~ (sign > 0 ? u64(0x100) : u64(0x200)),
            {planter_x, ground + .96, planter_z},
            planter_index < 2 ? f32(.70) : f32(.82),
            rotation + f32(planter_index) * math.PI * .5,
            detail_floor = .Medium,
            maturity = .82,
        )
    }

    service_position := airport_service_position(p)
    world_airport_box_rotated(
        {service_position.x, ground + MARTA_STOOL_HEIGHT - .06, service_position.z},
        {.62, .12, .54},
        rotation,
        .Bench_Slatted_Hardwood,
    )
    stool_leg_offsets := [4][2]f32{{-.23, -.19}, {-.23, .19}, {.23, -.19}, {.23, .19}}
    for offset in stool_leg_offsets {
        leg_x, leg_z := world_rotate_xz(p.x, p.z, offset.x, AIRPORT_ARCADE_CENTER_Z + offset.y, rotation)
        world_airport_box_rotated({leg_x, ground + .295, leg_z}, {.10, .27, .10}, rotation, .Painted_Steel)
    }
    clear(&cache.prefix_vertices)
    append(&cache.prefix_vertices, ..world_renderer.vertices[first_vertex:windsock_first])
    clear(&cache.suffix_vertices)
    append(&cache.suffix_vertices, ..world_renderer.vertices[windsock_end:])
    cache.terrain_revision = editor.terrain_revision
    cache.plant_lods = plant_lods
    cache.valid = true
}

world_marta :: proc(editor: ^Editor) {
    if !editor.in_map || !editor.libellula_visible do return
    service_position := airport_service_position(editor.attendant_position)
    if !world_sphere_in_view(editor, service_position + third_person.Vec3{0, 1.2, 0}, 2, 4) do return
    delta := third_person.Vec3 {
        editor.player.position.x - service_position.x,
        0,
        editor.player.position.z - service_position.z,
    }
    facing := math.atan2(-delta.x, -delta.z)
    position := service_position
    position.y += MARTA_STOOL_HEIGHT
    world_mouse_model(
        editor,
        {
            position = position,
            rotation = math.PI - facing,
            build = .88,
            snout_length = 1.12,
            accessory = .Flower,
            grounded = false,
        },
    )
    if story.resident_has_unseen_action(&editor.story_state, .Marta) {
        world_mouse_interaction_indicator(editor, position)
    }
}

world_marin :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map || east_marina_plan(editor) == nil do return
    position := marin_position(editor)
    if !world_sphere_in_view(editor, position + third_person.Vec3{0, 1.2, 0}, 2, 4) do return
    delta := third_person.Vec3{editor.player.position.x - position.x, 0, editor.player.position.z - position.z}
    facing := math.atan2(-delta.x, -delta.z)
    world_mouse_model(
        editor,
        {
            position = position,
            rotation = math.PI - facing,
            build = 1.05,
            snout_length = .96,
            accessory = .Paper_Boat,
            grounded = true,
        },
    )
    world_mouse_interaction_indicator(editor, position)
}

world_gerta :: proc(editor: ^Editor) {
    if !editor.in_map || !editor.libellula_visible do return
    service_position := airport_service_position(editor.gerta_position)
    if !world_sphere_in_view(editor, service_position + third_person.Vec3{0, 1.2, 0}, 2, 4) do return
    delta := third_person.Vec3 {
        editor.player.position.x - service_position.x,
        0,
        editor.player.position.z - service_position.z,
    }
    facing := math.atan2(-delta.x, -delta.z)
    position := service_position
    position.y += MARTA_STOOL_HEIGHT
    world_mouse_model(
        editor,
        {
            position = position,
            rotation = math.PI - facing,
            build = 1.16,
            snout_length = .92,
            accessory = .Flower,
            accessory_side = 1,
            grounded = false,
        },
    )
    if story.resident_has_unseen_action(&editor.story_state, .Gerta) {
        world_mouse_interaction_indicator(editor, position)
    }
}

world_mouse_interaction_indicator :: proc(editor: ^Editor, mouse_position: third_person.Vec3) {
    if editor == nil || editor.pilot.mode != .On_Foot || editor.attendant_dialogue_open || pause_menu_is_open(editor) {
        return
    }

    // Crossed slabs keep the punctuation legible from every approach without
    // requiring a screen-space overlay or a camera-facing render path.
    bob := f32(math.sin(canvas2d.GetTime() * 3.2)) * .055
    center := third_person.Vec3{mouse_position.x, mouse_position.y + 1.18 + bob, mouse_position.z}
    gold := canvas2d.Color{247, 191, 54, 255}
    shadow := canvas2d.Color{91, 57, 29, 255}

    rotations := [2]f32{0, math.PI * .5}
    for rotation in rotations {
        world_box_rotated({center.x, center.y + .17, center.z}, {.105, .34, .045}, rotation, shadow)
        world_box_rotated({center.x, center.y + .18, center.z}, {.065, .30, .065}, rotation, gold)
        world_box_rotated({center.x, center.y - .10, center.z}, {.12, .12, .055}, rotation, shadow)
        world_box_rotated({center.x, center.y - .10, center.z}, {.08, .08, .075}, rotation, gold)
    }
}

Town_Mouse :: struct {
    lateral:      f32,
    outward:      f32,
    facing:       f32,
    scale:        f32,
    build:        f32,
    snout_length: f32,
    accessory:    Mouse_Accessory,
    fur:          Mouse_Fur,
    pattern:      Mouse_Fur_Pattern,
    scarf:        bool,
    scarf_color:  canvas2d.Color,
}

story_resident_town_slot :: proc(resident: story.Resident) -> (island_index, resident_index: int, ok: bool) {
    switch resident {
    case .Niko:
        return 0, 0, true
    case .Bojan:
        return 0, 2, true
    case .Iva:
        return 1, 1, true
    case .Zora:
        return 1, 5, true
    case .Vesna:
        return 0, 4, true
    case .Petar:
        return 0, 6, true
    case .Anica:
        return 1, 6, true
    case .Mirna:
        return 1, 3, true
    case .Marta, .Toma, .Lena:
        return 0, 0, false
    case .Gerta:
        return 0, 0, false
    }
    return 0, 0, false
}

world_town_mouse_frontage_pose :: proc(
    frontage: terrain.Structure,
    project: ^terrain.Project,
    lateral, outward: f32,
) -> (
    x, z, rotation: f32,
) {
    entrance := settlement_structure_front_door_point(frontage, .22, project)
    edge := settlement_access_structure_edge(frontage, int(frontage.entrance_side))
    point := entrance + edge.tangent * lateral + edge.outward * outward
    rotation = math.atan2(edge.outward[1], edge.outward[0])
    return point[0], point[1], rotation
}
