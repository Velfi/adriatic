package main
import "core:math"
import "core:testing"

import atmosphere "../packages/atmosphere"
import dio "../packages/dio"
import flight "../packages/flight"
import mouse_kinematics "../packages/mouse_kinematics"
import third_person "../packages/third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

mouse_surface_height_for_model :: proc(editor: ^Editor, x, z: f32) -> f32 {
    cache := town_mouse_ground_cache_context
    if cache == nil do return mouse_surface_height(editor, x, z)
    sample_index := cache.cursor
    cache.cursor += 1
    if cache.reuse && sample_index < cache.entry.ground_sample_count {
        world_renderer.town_mouse_ground_cache_hits += 1
        return cache.entry.ground_samples[sample_index]
    }

    height := mouse_surface_height(editor, x, z)
    world_renderer.town_mouse_ground_cache_misses += 1
    if sample_index < len(cache.entry.ground_samples) {
        cache.entry.ground_samples[sample_index] = height
        cache.entry.ground_sample_count = max(cache.entry.ground_sample_count, sample_index + 1)
    }
    return height
}

MOUSE_CONTACT_SKIN :: f32(.006)

mouse_ground_contact :: proc(
    editor: ^Editor,
    point: third_person.Vec3,
    half_height: f32,
    planted: bool,
) -> third_person.Vec3 {
    floor := mouse_surface_height_for_model(editor, point.x, point.z) + half_height + MOUSE_CONTACT_SKIN
    result := point
    result.y = planted ? floor : max(result.y, floor)
    return result
}

mouse_clamp_endpoint_reach :: proc(
    root: third_person.Vec3,
    target: ^third_person.Vec3,
    minimum_reach, maximum_reach: f32,
) {
    if target == nil do return
    delta := third_person.Vec3{target.x - root.x, target.y - root.y, target.z - root.z}
    distance := linalg.length(delta)
    if distance <= .0001 {
        if minimum_reach > .0001 {
            target^ = {root.x, root.y, root.z + minimum_reach}
        }
        return
    }
    clamped_distance := clamp(distance, minimum_reach, maximum_reach)
    if math.abs(clamped_distance - distance) <= .0001 do return
    scale := clamped_distance / distance
    target^ = {root.x + delta.x * scale, root.y + delta.y * scale, root.z + delta.z * scale}
}

mouse_clamp_ground_contact_reach :: proc(root: third_person.Vec3, target: ^third_person.Vec3, maximum_reach: f32) {
    if target == nil do return
    dy := target.y - root.y
    if math.abs(dy) >= maximum_reach {
        // A target beyond the vertical reach cannot remain a ground contact:
        // the analytic solve would clamp its internal triangle while leaving
        // the rendered paw at the impossible endpoint, visibly splitting the
        // limb. Preserve direction and keep the complete endpoint reachable.
        target.x = root.x
        target.y = root.y + math.sign(dy) * maximum_reach
        target.z = root.z
        return
    }
    horizontal_delta := [2]f32{target.x - root.x, target.z - root.z}
    horizontal_distance := linalg.length(horizontal_delta)
    horizontal_limit := f32(math.sqrt(f64(max(maximum_reach * maximum_reach - dy * dy, f32(0)))))
    if horizontal_distance <= horizontal_limit || horizontal_distance <= .0001 do return
    scale := horizontal_limit / horizontal_distance
    target.x = root.x + horizontal_delta[0] * scale
    target.z = root.z + horizontal_delta[1] * scale
}

mouse_constrain_hind_chain :: proc(
    points: ^[4]third_person.Vec3,
    lengths: [3]f32,
    anatomical_forward: third_person.Vec3,
) {
    if points == nil do return
    root, target := points[0], points[3]
    root_to_target := third_person.Vec3{target.x - root.x, target.y - root.y, target.z - root.z}
    distance := linalg.length(root_to_target)
    total := lengths[0] + lengths[1] + lengths[2]
    if distance > total - .0001 {
        mouse_clamp_endpoint_reach(root, &target, 0, total - .0001)
        root_to_target = {target.x - root.x, target.y - root.y, target.z - root.z}
        distance = linalg.length(root_to_target)
    }
    remaining := mouse_kinematics.stable_distal_span(distance, lengths[0], lengths[1], lengths[2])
    // Two nested analytic solves preserve all three segment lengths and both
    // endpoints exactly. Stable anatomical poles retain the zig-zag topology,
    // while the phase-independent distal span prevents knee/hock accordion.
    knee := mouse_kinematics.solve_two_bone(
        root,
        target,
        mouse_kinematics.hind_knee_pole(anatomical_forward),
        lengths[0],
        remaining,
    )
    hock := mouse_kinematics.solve_two_bone(
        knee,
        target,
        mouse_kinematics.hind_hock_pole(anatomical_forward),
        lengths[1],
        lengths[2],
    )
    points^ = {root, knee, hock, target}
}

Mouse_Accessory :: enum {
    None,
    Goggles,
    Flower,
    Acorn_Cap,
    Bottle_Cap,
    Paper_Boat,
    Chef_Hat,
    Ushanka,
    Beret,
    Alpine_Hat,
    Flat_Cap,
    Sailor_Hat,
}

Mouse_Fur :: enum {
    Chestnut,
    Silver,
    Cream,
    Soot,
    Russet,
    White,
}

Mouse_Fur_Pattern :: enum {
    Solid,
    Pale_Belly,
    Hooded,
    Piebald,
    Dorsal_Stripe,
    Masked,
}

// Approximate the coat immediately surrounding a limb socket. The torso has
// denser per-vertex patterning, but carrying its dominant socket color into the
// first limb ring prevents the appendage from beginning at a hard color seam.
mouse_limb_socket_color :: proc(
    pattern: Mouse_Fur_Pattern,
    fur, fur_dark, fur_light: canvas2d.Color,
    side: f32,
    hind: bool,
) -> canvas2d.Color {
    marking := color_lerp(fur_light, {247, 239, 218, 255}, .72)
    switch pattern {
    case .Pale_Belly:
        return color_lerp(fur, marking, hind ? f32(.76) : f32(.66))
    case .Hooded:
        return color_lerp(fur, marking, hind ? f32(.90) : f32(.72))
    case .Piebald:
        pale_socket := hind ? side > 0 : side < 0
        if pale_socket do return color_lerp(fur, marking, .88)
    case .Dorsal_Stripe:
    // Limb sockets sit below the dorsal stripe.
    case .Masked:
    // The mask is confined to the head.
    case .Solid:
    }
    return color_lerp(fur, fur_dark, hind ? f32(.04) : f32(.08))
}

Mouse_Model :: struct {
    position:           third_person.Vec3,
    rotation:           f32,
    // Zero retains the canonical proportions so existing call sites do not
    // need to opt in. Town residents use these to keep distinct silhouettes.
    build:              f32,
    snout_length:       f32,
    accessory:          Mouse_Accessory,
    accessory_side:     f32,
    fur:                Mouse_Fur,
    pattern:            Mouse_Fur_Pattern,
    scarf_enabled:      bool,
    scarf_color:        canvas2d.Color,
    mailbag_enabled:    bool,
    preview:            bool,
    player_controlled:  bool,
    track_paw_plants:   bool,
    grounded:           bool,
    hide_tail:          bool,
    hide_hind_feet:     bool,
    driving_pose:       bool,
    drive_steering:     f32,
    drive_acceleration: f32,
    gait_preview:       bool,
    gait_speed:         f32,
    gait_phase:         f32,
}

// world_mouse_model builds geometry in a yaw-only frame because ordinary mice
// stay aligned to world up. Aircraft occupants need one additional parent
// transform: recover each emitted vertex's yaw-local coordinates, then place
// it in the aircraft's full -right/up/forward presentation basis so pitch and
// roll are inherited together with translation and heading. The mouse and
// aircraft face opposite directions in their authored local frames, so both
// horizontal axes must flip: that is a proper 180-degree rotation around up.
// Flipping only forward reflects the mesh and reverses its triangle winding.
world_aircraft_occupant_vector :: #force_inline proc(
    basis: flight.Basis,
    local_x, local_y, local_z: f32,
) -> third_person.Vec3 {
    return {
        -basis.right.x * local_x + basis.up.x * local_y + basis.forward.x * local_z,
        -basis.right.y * local_x + basis.up.y * local_y + basis.forward.y * local_z,
        -basis.right.z * local_x + basis.up.z * local_y + basis.forward.z * local_z,
    }
}

when ODIN_TEST {
    @(test)
    aircraft_occupant_parent_faces_forward_and_preserves_handedness :: proc(t: ^testing.T) {
        basis := flight.identity_basis()
        testing.expect_value(t, world_aircraft_occupant_vector(basis, 1, 0, 0), third_person.Vec3{-1, 0, 0})
        testing.expect_value(t, world_aircraft_occupant_vector(basis, 0, 1, 0), third_person.Vec3{0, 1, 0})
        testing.expect_value(t, world_aircraft_occupant_vector(basis, 0, 0, 1), basis.forward)
    }
}

world_mouse_model_parented :: proc(editor: ^Editor, model: Mouse_Model, basis: flight.Basis) {
    first_vertex := len(world_renderer.vertices)
    world_mouse_model(editor, model)

    yaw_right := third_person.Vec3{math.cos(model.rotation), 0, math.sin(model.rotation)}
    yaw_forward := third_person.Vec3{-math.sin(model.rotation), 0, math.cos(model.rotation)}
    origin := model.position
    for index in first_vertex ..< len(world_renderer.vertices) {
        vertex := &world_renderer.vertices[index]
        delta := third_person.Vec3 {
            vertex.position[0] - origin.x,
            vertex.position[1] - origin.y,
            vertex.position[2] - origin.z,
        }
        local_x := delta.x * yaw_right.x + delta.z * yaw_right.z
        local_y := delta.y
        local_z := delta.x * yaw_forward.x + delta.z * yaw_forward.z
        parented_position := world_aircraft_occupant_vector(basis, local_x, local_y, local_z)
        vertex.position = {
            origin.x + parented_position.x,
            origin.y + parented_position.y,
            origin.z + parented_position.z,
        }

        normal := third_person.Vec3{vertex.normal[0], vertex.normal[1], vertex.normal[2]}
        normal_x := normal.x * yaw_right.x + normal.z * yaw_right.z
        normal_y := normal.y
        normal_z := normal.x * yaw_forward.x + normal.z * yaw_forward.z
        parented_normal := world_aircraft_occupant_vector(basis, normal_x, normal_y, normal_z)
        vertex.normal = {parented_normal.x, parented_normal.y, parented_normal.z}
    }
}

world_mouse_model_scaled :: proc(editor: ^Editor, model: Mouse_Model, scale: f32) {
    first_vertex := len(world_renderer.vertices)
    world_mouse_model(editor, model)
    safe_scale := max(scale, f32(.01))
    for index in first_vertex ..< len(world_renderer.vertices) {
        vertex := &world_renderer.vertices[index]
        vertex.position = {
            model.position.x + (vertex.position[0] - model.position.x) * safe_scale,
            model.position.y + (vertex.position[1] - model.position.y) * safe_scale,
            model.position.z + (vertex.position[2] - model.position.z) * safe_scale,
        }
    }
}

town_mouse_ground_cache_matches :: proc(
    entry: ^Town_Mouse_Geometry_Cache_Entry,
    model: Mouse_Model,
    scale: f32,
    project_revision, terrain_revision: u64,
) -> bool {
    return(
        entry != nil &&
        entry.ground_valid &&
        entry.ground_model == model &&
        entry.ground_scale == scale &&
        entry.ground_project_revision == project_revision &&
        entry.ground_terrain_revision == terrain_revision \
    )
}

when ODIN_TEST {
    @(test)
    town_mouse_ground_cache_keys_stationary_model_and_world_revisions :: proc(t: ^testing.T) {
        model := Mouse_Model {
            position = {12, 3, -8},
            rotation = .4,
            build    = 1.1,
            grounded = true,
        }
        entry := Town_Mouse_Geometry_Cache_Entry {
            ground_valid            = true,
            ground_model            = model,
            ground_scale            = .9,
            ground_project_revision = 7,
            ground_terrain_revision = 11,
        }
        testing.expect(t, town_mouse_ground_cache_matches(&entry, model, .9, 7, 11))
        moved := model
        moved.position.x += .01
        testing.expect(t, !town_mouse_ground_cache_matches(&entry, moved, .9, 7, 11))
        ungrounded := model
        ungrounded.grounded = false
        testing.expect(t, !town_mouse_ground_cache_matches(&entry, ungrounded, .9, 7, 11))
        testing.expect(t, !town_mouse_ground_cache_matches(&entry, model, 1, 7, 11))
        testing.expect(t, !town_mouse_ground_cache_matches(&entry, model, .9, 8, 11))
        testing.expect(t, !town_mouse_ground_cache_matches(&entry, model, .9, 7, 12))
    }
}

world_town_mouse_model_scaled_cached :: proc(editor: ^Editor, model: Mouse_Model, scale: f32, cache_index: int) {
    if editor == nil || cache_index < 0 || cache_index >= TOWN_MOUSE_CACHE_COUNT {
        world_mouse_model_scaled(editor, model, scale)
        return
    }
    entry := &world_renderer.town_mouse_geometry_cache[cache_index]
    wind := model.scarf_enabled ? editor.atmosphere.weather.wind : [2]f32{}
    if entry.valid &&
       entry.model == model &&
       entry.scale == scale &&
       entry.wind == wind &&
       entry.project_revision == editor.project.revision &&
       entry.terrain_revision == editor.terrain_revision {
        world_renderer.town_mouse_cache_reuses += 1
        profile := dio.flame_graph_begin(dio.flame_graph_current(), "town_mouse_cache_reuse")
        append(&world_renderer.vertices, ..entry.vertices[:])
        _ = dio.flame_graph_end(dio.flame_graph_current(), profile)
        return
    }
    world_renderer.town_mouse_cache_builds += 1
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "town_mouse_cache_build")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)

    first := len(world_renderer.vertices)
    ground_cache_reuse := town_mouse_ground_cache_matches(
        entry,
        model,
        scale,
        editor.project.revision,
        editor.terrain_revision,
    )
    if !ground_cache_reuse do entry.ground_sample_count = 0
    ground_cache := Town_Mouse_Ground_Cache_Context {
        entry = entry,
        reuse = ground_cache_reuse,
    }
    town_mouse_ground_cache_context = &ground_cache
    world_mouse_model_scaled(editor, model, scale)
    town_mouse_ground_cache_context = nil
    entry.ground_valid = true
    entry.ground_model = model
    entry.ground_scale = scale
    entry.ground_project_revision = editor.project.revision
    entry.ground_terrain_revision = editor.terrain_revision
    clear(&entry.vertices)
    if first < len(world_renderer.vertices) {
        append(&entry.vertices, ..world_renderer.vertices[first:])
    }
    entry.valid = true
    entry.model = model
    entry.scale = scale
    // Background residents use their first generated pose as a baked mesh.
    // Their foreground dialogue portraits own the animated 30 Hz path. Keeping
    // map time out of this cache key prevents procedural mesh generation from
    // returning to the frame builder as frame rate falls.
    entry.animation_bucket = 0
    entry.wind = wind
    entry.project_revision = editor.project.revision
    entry.terrain_revision = editor.terrain_revision
}
