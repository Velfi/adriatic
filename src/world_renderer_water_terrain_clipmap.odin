package main
import "core:math"

import dio "../packages/dio"
import roads "../packages/roads"
import spring_river "../packages/spring_river"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_roads_transient :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_roads_transient")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil do return
    graph := &editor.project.road_graph
    world_spline_steps(editor, graph)
    if editor.in_map || !editor.road_mode || editor.capture_world_only do return
    if editor.cursor_hit {
        cursor := roads.Vec3 {
            editor.cursor_world_x,
            terrain.sample_height(&editor.project, 0, editor.cursor_world_x, editor.cursor_world_z),
            editor.cursor_world_z,
        }
        preview_color := canvas2d.Color{101, 226, 203, 150}
        if editor.road_preview_status != .Idle && editor.road_preview_status != .Valid {
            preview_color = {229, 105, 90, 175}
        }
        // The road cursor shows the actual shoulder and paved widths, without
        // borrowing the terrain brush's hardness rings.
        world_brush_disc(
            editor,
            cursor.x,
            cursor.z,
            editor.road_width * .5 + editor.road_shoulder_width,
            .13,
            {preview_color.r, preview_color.g, preview_color.b, 70},
        )
        world_brush_disc(editor, cursor.x, cursor.z, editor.road_width * .5, .15, preview_color)
    }
    if (editor.road_preview_status == .Valid || editor.road_preview_status == .Stale) &&
       editor.road_preview_first_edge >= 0 {
        preview := &editor.road_preview_graph
        shoulder_color := canvas2d.Color{101, 226, 203, 68}
        surface_color := canvas2d.Color{101, 226, 203, 150}
        if editor.road_preview_status == .Stale {
            shoulder_color = {190, 198, 203, 48}
            surface_color = {190, 198, 203, 100}
        }
        for edge in preview.edges[editor.road_preview_first_edge:preview.edge_count] {
            previous := roads.edge_point(preview, edge, 0)
            for segment in 1 ..= 24 {
                current := roads.edge_point(preview, edge, f32(segment) / 24)
                world_road_editor_link(
                    previous,
                    current,
                    editor.road_width + editor.road_shoulder_width * 2,
                    shoulder_color,
                )
                world_road_editor_link(previous, current, editor.road_width, surface_color)
                previous = current
            }
        }
    } else if editor.road_selected_node >= 0 && editor.road_preview_status != .Idle {
        start := graph.nodes[editor.road_selected_node].position
        end :=
            editor.road_preview_snap.valid ? editor.road_preview_snap.position : roads.Vec3{editor.cursor_world_x, terrain.sample_height(&editor.project, 0, editor.cursor_world_x, editor.cursor_world_z), editor.cursor_world_z}
        world_road_editor_link(start, end, .55, {229, 105, 90, 190})
    }
    if editor.road_preview_snap.valid {
        snap := editor.road_preview_snap.position
        snap_color := canvas2d.Color{220, 226, 231, 190}
        if editor.road_preview_snap.kind == .Edge || editor.road_preview_snap.kind == .Node {
            snap_color = {69, 224, 205, 235}
        }
        world_box({snap.x, snap.y + .8, snap.z}, {2.4, 1.6, 2.4}, snap_color)
        guide := editor.road_preview_snap.guide_from
        if editor.road_preview_snap.kind == .Angle ||
           editor.road_preview_snap.kind == .Tangent ||
           editor.road_preview_snap.kind == .Perpendicular {
            world_road_editor_link(guide, snap, .32, {224, 229, 233, 145})
        }
    }
    if editor.road_construction_mode == .Authored_Curve &&
       editor.road_selected_node >= 0 &&
       (editor.road_construction_phase == .Choose_End || editor.road_construction_phase == .Drag_End_Tangent) {
        start := graph.nodes[editor.road_selected_node].position
        world_road_editor_link(start, editor.road_preview_control_from, .5, {224, 229, 233, 165})
        world_box(editor.road_preview_control_from, {2, 2, 2}, {83, 232, 225, 235})
        if editor.road_construction_phase == .Drag_End_Tangent {
            world_road_editor_link(
                editor.road_preview_endpoint,
                editor.road_preview_control_to,
                .5,
                {224, 229, 233, 165},
            )
            world_box(editor.road_preview_control_to, {2, 2, 2}, {83, 232, 225, 235})
        }
    }
    for node, index in graph.nodes[:graph.node_count] {
        selected := index == editor.road_selected_node
        node_radius := road_snap_world_radius(editor, node.position)
        if !world_sphere_in_view(editor, {node.position.x, node.position.y + .8, node.position.z}, node_radius, 1) {
            continue
        }
        hovered := !selected && road_node_at(editor, editor.cursor_world_x, editor.cursor_world_z) == index
        world_road_editor_grip(editor, node.position, hovered, selected)
    }
    if editor.road_selected_node < 0 || editor.road_selected_node >= graph.node_count do return
    for edge, edge_index in graph.edges[:graph.edge_count] {
        if edge.from != editor.road_selected_node && edge.to != editor.road_selected_node do continue
        handle_index := edge.from == editor.road_selected_node ? 0 : 1
        anchor := roads.edge_point(graph, edge, .5)
        control := handle_index == 0 ? edge.control_from : edge.control_to
        link_center := (anchor + control) * .5
        link_radius := linalg.length(control - anchor) * .5 + road_snap_world_radius(editor, control)
        if !world_sphere_in_view(editor, link_center, link_radius, 2) do continue
        hovered := editor.road_hover_edge == edge_index && editor.road_hover_handle == handle_index
        active := editor.road_drag_edge == edge_index && editor.road_drag_handle == handle_index
        anchor.y += .3
        control.y += .3
        stem_color := canvas2d.Color{117, 216, 230, 190}
        if hovered do stem_color = {230, 246, 249, 230}
        if active do stem_color = {255, 205, 70, 235}
        world_road_editor_link(anchor, control, active ? f32(.8) : (hovered ? f32(.68) : f32(.46)), stem_color)
        world_road_editor_grip(editor, control, hovered, active)
    }
}

world_ocean :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    // Bathymetry owns this exact camera-local rectangle. The far ocean is
    // clipped around it below, so the two water meshes never overlap and
    // therefore cannot z-fight regardless of camera distance or depth-buffer
    // precision.
    local_cell := f32(24)
    local_extent := f32(1800)
    local_divisions := int(math.ceil(f64(local_extent * 2 / local_cell)))
    local_center_x := f32(math.floor(f64(camera.position.x / local_cell))) * local_cell
    local_center_z := f32(math.floor(f64(camera.position.z / local_cell))) * local_cell
    local_min_x := local_center_x - local_extent
    local_max_x := local_center_x + local_extent
    local_min_z := local_center_z - local_extent
    local_max_z := local_center_z + local_extent

    extent := editor.in_map ? f32(12000) : f32(15000)
    divisions := editor.in_map ? 48 : 32
    cell := extent * 2 / f32(divisions)
    // A snapped tiled field surrounds the camera in every direction. Unlike the
    // former forward slab, it has no near edge for a high, downward-looking
    // camera to expose at the bottom of the viewport.
    center_x := f32(math.floor(f64(camera.position.x / cell))) * cell
    center_z := f32(math.floor(f64(camera.position.z / cell))) * cell
    // Gameplay water sits just above the mathematical sea datum. Placing it
    // eight centimetres below allowed the gently descending generated beach
    // to protrude through the plane as dark triangulated wedges.
    ocean_y := editor.project.sea_level + (editor.in_map ? f32(.02) : f32(-2))
    if lab_scene_is_active(editor, "markov-island") {
        // Leave a small guaranteed gap above the lab seabed. Mixed shoreline
        // triangles then remain behind the flat water instead of drawing a
        // pale, clipmap-shaped shelf outline.
        ocean_y = editor.project.sea_level - 1.9
    }
    color := canvas2d.Color{48, 112, 142, 255}
    for z_index in 0 ..< divisions {
        z0 := center_z - extent + f32(z_index) * cell
        z1 := z0 + cell
        for x_index in 0 ..< divisions {
            x0 := center_x - extent + f32(x_index) * cell
            x1 := x0 + cell
            // Reverse winding so the ocean's upward face is the front (CCW) face
            // and survives back-face culling from a downward-looking camera.
            if x1 <= local_min_x || x0 >= local_max_x || z1 <= local_min_z || z0 >= local_max_z {
                world_water_quad({x0, ocean_y, z0}, {x0, ocean_y, z1}, {x1, ocean_y, z1}, {x1, ocean_y, z0}, color)
                continue
            }

            // Clip a coarse far-ocean cell into four non-overlapping strips
            // around the local rectangle. Their shared boundary is harmless:
            // no fragment has two water surfaces competing for its depth.
            overlap_min_x := max(x0, local_min_x)
            overlap_max_x := min(x1, local_max_x)
            overlap_min_z := max(z0, local_min_z)
            overlap_max_z := min(z1, local_max_z)
            if x0 < overlap_min_x {
                world_water_quad(
                    {x0, ocean_y, z0},
                    {x0, ocean_y, z1},
                    {overlap_min_x, ocean_y, z1},
                    {overlap_min_x, ocean_y, z0},
                    color,
                )
            }
            if overlap_max_x < x1 {
                world_water_quad(
                    {overlap_max_x, ocean_y, z0},
                    {overlap_max_x, ocean_y, z1},
                    {x1, ocean_y, z1},
                    {x1, ocean_y, z0},
                    color,
                )
            }
            if z0 < overlap_min_z {
                world_water_quad(
                    {overlap_min_x, ocean_y, z0},
                    {overlap_min_x, ocean_y, overlap_min_z},
                    {overlap_max_x, ocean_y, overlap_min_z},
                    {overlap_max_x, ocean_y, z0},
                    color,
                )
            }
            if overlap_max_z < z1 {
                world_water_quad(
                    {overlap_min_x, ocean_y, overlap_max_z},
                    {overlap_min_x, ocean_y, z1},
                    {overlap_max_x, ocean_y, z1},
                    {overlap_max_x, ocean_y, overlap_max_z},
                    color,
                )
            }
        }
    }

    // Sample terrain-dependent shallowness on a camera-local grid. The former
    // full-world layer used 125 m cells, making its interpolated depth signal
    // expose enormous square triangles around every generated shoreline.
    // A 24 m local field is inexpensive enough for immediate geometry, follows
    // the active coast, and fades naturally into the uniform far ocean once
    // its boundary reaches deep water.
    // A small height difference remains useful for hiding the shared boundary,
    // but correctness no longer depends on it: the two meshes have no area
    // overlap.
    local_ocean_y := ocean_y + f32(.004)
    for z_index in 0 ..< local_divisions {
        z0 := local_center_z - local_extent + f32(z_index) * local_cell
        z1 := z0 + local_cell
        for x_index in 0 ..< local_divisions {
            x0 := local_center_x - local_extent + f32(x_index) * local_cell
            x1 := x0 + local_cell
            world_ocean_quad(
                editor,
                {x0, local_ocean_y, z0},
                {x0, local_ocean_y, z1},
                {x1, local_ocean_y, z1},
                {x1, local_ocean_y, z0},
                color,
            )
        }
    }
}

world_river_water_spline :: proc(editor: ^Editor, spline: ^terrain.River_Water_Spline) {
    if editor == nil || spline == nil || spline.point_count < 2 do return
    count := clamp(spline.point_count, 0, terrain.RIVER_WATER_POINT_CAPACITY)
    // The terrain clipmap interpolates independently from the authored river
    // cross-sections. Give the visible surface enough overlap and clearance to
    // remain continuous through that envelope, especially from an aircraft.
    // This is presentation margin only; the narrower sampled bed still owns
    // terrain carving and traversal.
    surface_width_scale := f32(.58)
    surface_min_half_width := f32(1.25)
    surface_clearance := f32(.12)
    color := canvas2d.Color{41, 132, 154, 250}

    // The generator's first width describes a spring basin, not the outgoing
    // channel. Rendering it as a strip cross-section produces long wedges as
    // that width contracts over the first few tightly-spaced points. Keep the
    // basin round and clamp the strip to its settled downstream width.
    source := spline.points[0]
    // The outgoing ribbon begins inside this basin. Keep the basin a hair
    // above that overlapping strip so depth testing has one stable owner at
    // the source instead of alternating between coplanar water triangles.
    source_cap_bias := f32(.004)
    source_y := max(source.water_level, editor.project.sea_level) + surface_clearance + source_cap_bias
    source_center := third_person.Vec3{source.position[0], source_y, source.position[1]}
    source_radius := max(source.width * .5, surface_min_half_width)
    source_segments := 20
    for segment in 0 ..< source_segments {
        angle_a := f32(segment) / f32(source_segments) * math.PI * 2
        angle_b := f32(segment + 1) / f32(source_segments) * math.PI * 2
        edge_a :=
            source_center + third_person.Vec3{math.cos(angle_a) * source_radius, 0, math.sin(angle_a) * source_radius}
        edge_b :=
            source_center + third_person.Vec3{math.cos(angle_b) * source_radius, 0, math.sin(angle_b) * source_radius}
        world_water_triangle_colored(source_center, edge_b, edge_a, color, color, color)
    }
    settled_index := clamp(count / 12, 1, count - 1)
    source_channel_half_width := max(spline.points[settled_index].width * surface_width_scale, surface_min_half_width)

    for point_index in 0 ..< count - 1 {
        a, b := spline.points[point_index], spline.points[point_index + 1]
        // The ocean owns the final sea-level portion. Stop emitting the river
        // ribbon once both cross-sections have merged into that plane.
        if a.water_level <= editor.project.sea_level + .01 && b.water_level <= editor.project.sea_level + .01 {
            continue
        }
        previous := spline.points[max(point_index - 1, 0)].position
        next := spline.points[min(point_index + 2, count - 1)].position
        tangent_a := spring_river.normalize_or(a.position - previous, b.position - a.position)
        tangent_b := spring_river.normalize_or(next - b.position, b.position - a.position)
        side_a := spring_river.Vec2{-tangent_a[1], tangent_a[0]}
        side_b := spring_river.Vec2{-tangent_b[1], tangent_b[0]}
        half_width_a := max(a.width * surface_width_scale, surface_min_half_width)
        half_width_b := max(b.width * surface_width_scale, surface_min_half_width)
        half_width_a = min(half_width_a, source_channel_half_width)
        half_width_b = min(half_width_b, source_channel_half_width)
        y_a := max(a.water_level, editor.project.sea_level) + surface_clearance
        y_b := max(b.water_level, editor.project.sea_level) + surface_clearance
        left_a := third_person.Vec3 {
            a.position[0] + side_a[0] * half_width_a,
            y_a,
            a.position[1] + side_a[1] * half_width_a,
        }
        left_b := third_person.Vec3 {
            b.position[0] + side_b[0] * half_width_b,
            y_b,
            b.position[1] + side_b[1] * half_width_b,
        }
        right_b := third_person.Vec3 {
            b.position[0] - side_b[0] * half_width_b,
            y_b,
            b.position[1] - side_b[1] * half_width_b,
        }
        right_a := third_person.Vec3 {
            a.position[0] - side_a[0] * half_width_a,
            y_a,
            a.position[1] - side_a[1] * half_width_a,
        }
        world_water_quad(left_a, left_b, right_b, right_a, color)
    }
}

world_river_water :: proc(editor: ^Editor) {
    if editor == nil do return
    for &spline in editor.project.river_water_splines {
        world_river_water_spline(editor, &spline)
    }
}

world_bathymetry :: proc(editor: ^Editor) {
    if editor == nil || editor.in_map do return
    camera_x, camera_z := editor.camera_pose.position.x, editor.camera_pose.position.z
    normal := third_person.Vec3{0, 1, 0}
    for &chunk in editor.project.bathymetry_chunks {
        origin_x := f32(chunk.chunk_x) * terrain.BATHYMETRY_CHUNK_SIZE
        origin_z := f32(chunk.chunk_z) * terrain.BATHYMETRY_CHUNK_SIZE
        if abs(origin_x - camera_x) > 512 || abs(origin_z - camera_z) > 512 do continue
        for z in 0 ..< terrain.BATHYMETRY_CHUNK_RESOLUTION - 1 {
            for x in 0 ..< terrain.BATHYMETRY_CHUNK_RESOLUTION - 1 {
                center_x := origin_x + (f32(x) + .5) * terrain.BATHYMETRY_CHUNK_SIZE / f32(terrain.BATHYMETRY_CHUNK_RESOLUTION - 1)
                center_z := origin_z + (f32(z) + .5) * terrain.BATHYMETRY_CHUNK_SIZE / f32(terrain.BATHYMETRY_CHUNK_RESOLUTION - 1)
                _, _, land := terrain.sample_land(&editor.project, 0, center_x, center_z)
                if land do continue
                i := z * terrain.BATHYMETRY_CHUNK_RESOLUTION + x
                i1 := i + 1
                i2 := i + terrain.BATHYMETRY_CHUNK_RESOLUTION
                i3 := i2 + 1
                cell := terrain.BATHYMETRY_CHUNK_SIZE / f32(terrain.BATHYMETRY_CHUNK_RESOLUTION - 1)
                a := third_person.Vec3{origin_x + f32(x) * cell, f32(chunk.heights[i]), origin_z + f32(z) * cell}
                b := third_person.Vec3{origin_x + f32(x) * cell, f32(chunk.heights[i2]), origin_z + f32(z + 1) * cell}
                c := third_person.Vec3{origin_x + f32(x + 1) * cell, f32(chunk.heights[i3]), origin_z + f32(z + 1) * cell}
                d := third_person.Vec3{origin_x + f32(x + 1) * cell, f32(chunk.heights[i1]), origin_z + f32(z) * cell}
                world_quad_colored_smooth_lit(a, b, c, d, normal, normal, normal, normal, canvas2d.Color{151, 137, 99, 255}, canvas2d.Color{151, 137, 99, 255}, canvas2d.Color{151, 137, 99, 255}, canvas2d.Color{151, 137, 99, 255}, .94)
            }
        }
    }
}

world_box :: proc(center, size: third_person.Vec3, color: canvas2d.Color) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p := [8]third_person.Vec3 {
        {center.x - x, center.y - y, center.z - z},
        {center.x + x, center.y - y, center.z - z},
        {center.x + x, center.y + y, center.z - z},
        {center.x - x, center.y + y, center.z - z},
        {center.x - x, center.y - y, center.z + z},
        {center.x + x, center.y - y, center.z + z},
        {center.x + x, center.y + y, center.z + z},
        {center.x - x, center.y + y, center.z + z},
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

@(no_instrumentation)
clipmap_vertex_color :: #force_inline proc(
    editor: ^Editor,
    level: int,
    x, z, height, transition_weight: f32,
) -> (
    canvas2d.Color,
    f32,
    third_person.Vec3,
) {
    cell := editor.project.levels[level].cell_size
    left := terrain.sample_clipmap_transition_height(&editor.project, level, x - cell, z, transition_weight)
    right := terrain.sample_clipmap_transition_height(&editor.project, level, x + cell, z, transition_weight)
    back := terrain.sample_clipmap_transition_height(&editor.project, level, x, z - cell, transition_weight)
    front := terrain.sample_clipmap_transition_height(&editor.project, level, x, z + cell, transition_weight)
    normal := linalg.normalize0(
        linalg.cross(third_person.Vec3{0, front - back, cell * 2}, third_person.Vec3{cell * 2, right - left, 0}),
    )
    painted := terrain.sample_render_material(&editor.project, level, x, z)
    // Expose pale Adriatic limestone only where the grade is genuinely
    // cliff-like. The broad transition avoids drawing a contour around the
    // threshold and leaves ordinary hills under their ground cover. Generated
    // coastal sand owns its faces at every grade: dune slip faces and blowouts
    // must remain sand rather than exposing the island's limestone treatment.
    cliff_weight := clamp((.91 - normal.y) / .24, 0, 1)
    cliff_weight = cliff_weight * cliff_weight * (3 - 2 * cliff_weight)
    if painted < 0 do cliff_weight = 0
    light := linalg.normalize0(third_person.Vec3{-.45, .85, -.3})
    shade := clamp(.48 + max(linalg.dot(normal, light), 0) * .52, .42, 1.05)
    fragment_dune_lighting := painted < 0
    base := terrain_color(max(height, editor.project.sea_level + .12), painted, editor.project.sea_level, x, z)
    limestone := terrain_color_variation(canvas2d.Color{222, 216, 188, 255}, x * .73, z * .73)
    ground_lit := canvas2d.Color {
        u8(clamp(f32(base.r) * (fragment_dune_lighting ? f32(1) : shade), 0, 255)),
        u8(clamp(f32(base.g) * (fragment_dune_lighting ? f32(1) : shade), 0, 255)),
        u8(clamp(f32(base.b) * (fragment_dune_lighting ? f32(1) : shade), 0, 255)),
        255,
    }
    // Sun-bleached limestone keeps a pale body even on a face turned away
    // from the key light; crushing it to the soil lighting floor makes the
    // same warm hue read as mud.
    limestone_shade := max(shade, f32(.68))
    limestone_lit := canvas2d.Color {
        u8(clamp(f32(limestone.r) * limestone_shade, 0, 255)),
        u8(clamp(f32(limestone.g) * limestone_shade, 0, 255)),
        u8(clamp(f32(limestone.b) * limestone_shade, 0, 255)),
        255,
    }
    return color_lerp(ground_lit, limestone_lit, cliff_weight), cliff_weight, normal
}

@(no_instrumentation)
clipmap_level_center :: proc(target: [2]f32, grid_cell: f32) -> [2]f32 {
    return {
        f32(math.round(f64(target[0] / grid_cell))) * grid_cell,
        f32(math.round(f64(target[1] / grid_cell))) * grid_cell,
    }
}

@(no_instrumentation)
clipmap_grid_cell :: #force_inline proc(editor: ^Editor, level: int) -> f32 {
    if editor == nil || level < 0 || level >= terrain.CLIPMAP_LEVELS do return 1
    cell := editor.project.levels[level].cell_size
    // The dedicated 513×513 innermost mesh samples at half a metre while
    // retaining the former 256 m footprint. The first outer ring samples its
    // native two-metre terrain level, avoiding an abrupt 8× jump across the
    // player-visible dune belt. Successive rings retain their established
    // doubled spacing and broad world coverage.
    if level == 0 do return cell * .5
    if level == 1 do return cell
    return cell * 2
}

@(no_instrumentation)
clipmap_grid_resolution :: #force_inline proc(level: int) -> int {
    return level == 0 ? CLIPMAP_INNER_GRID_RESOLUTION : CLIPMAP_GRID_RESOLUTION
}

// World views do not need sub-pixel terrain tessellation. Select the first
// clipmap whose vertex spacing is visible at the camera's distance from the
// terrain beneath its focus; that level becomes the solid center and coarser
// levels remain rings around it. Camera-to-focus distance alone is insufficient
// for aircraft because both points remain close together high above the land.
clipmap_first_render_level :: proc(editor: ^Editor, viewport_height: i32, focal_length: f32 = 1.35) -> int {
    if editor == nil || viewport_height <= 0 do return 0
    terrain_y := terrain.sample_height(&editor.project, 0, editor.camera_pose.target.x, editor.camera_pose.target.z)
    terrain_focus := third_person.Vec3{editor.camera_pose.target.x, terrain_y, editor.camera_pose.target.z}
    delta := editor.camera_pose.position - terrain_focus
    distance := f32(math.sqrt(f64(linalg.dot(delta, delta))))
    if distance <= .001 do return 0
    pixels_per_meter := focal_length * f32(viewport_height) * .5 / distance
    for level in 0 ..< terrain.CLIPMAP_LEVELS - 1 {
        if clipmap_grid_cell(editor, level) * pixels_per_meter >= CLIPMAP_MIN_VERTEX_SPACING_PIXELS {
            return level
        }
    }
    return terrain.CLIPMAP_LEVELS - 1
}

@(no_instrumentation)
clipmap_center_offset :: proc(
    old_center, new_center: [2]f32,
    grid_cell: f32,
    resolution: int = CLIPMAP_GRID_RESOLUTION,
) -> (
    [2]int,
    bool,
) {
    raw_x := (new_center[0] - old_center[0]) / grid_cell
    raw_z := (new_center[1] - old_center[1]) / grid_cell
    offset := [2]int{int(math.round(f64(raw_x))), int(math.round(f64(raw_z)))}
    aligned := abs(raw_x - f32(offset[0])) <= .001 && abs(raw_z - f32(offset[1])) <= .001
    within_grid := abs(offset[0]) < resolution && abs(offset[1]) < resolution
    return offset, aligned && within_grid
}

@(no_instrumentation)
clipmap_shift_source_for_resolution :: #force_inline proc(x, z: int, offset: [2]int, resolution: int) -> (int, bool) {
    source_x, source_z := x + offset[0], z + offset[1]
    retained := source_x >= 0 && source_x < resolution && source_z >= 0 && source_z < resolution
    if !retained do return 0, false
    return source_z * resolution + source_x, true
}

@(no_instrumentation)
clipmap_shift_source :: #force_inline proc(x, z: int, offset: [2]int) -> (int, bool) {
    return clipmap_shift_source_for_resolution(x, z, offset, CLIPMAP_GRID_RESOLUTION)
}

@(no_instrumentation)
clipmap_transition_weight :: #force_inline proc(level, x, z: int) -> f32 {
    resolution := clipmap_grid_resolution(level)
    // Doubling the vertex band on the two densest levels preserves their
    // previous four- and sixteen-metre world-space transition widths.
    transition_width := level <= 1 ? CLIPMAP_TRANSITION_WIDTH * 2 : CLIPMAP_TRANSITION_WIDTH
    edge_distance := min(min(x, z), min(resolution - 1 - x, resolution - 1 - z))
    if level >= terrain.CLIPMAP_LEVELS - 1 || edge_distance >= transition_width {
        return 0
    }
    weight := 1 - f32(edge_distance) / f32(transition_width)
    return weight * weight * (3 - 2 * weight)
}

clipmap_update_vertex :: proc(editor: ^Editor, vertices: []World_Vertex, level: int, center: [2]f32, x, z: int) {
    data := &editor.project.levels[level]
    grid_cell := clipmap_grid_cell(editor, level)
    resolution := clipmap_grid_resolution(level)
    half_grid := f32(resolution - 1) * .5
    world_x := center[0] + (f32(x) - half_grid) * grid_cell
    world_z := center[1] + (f32(z) - half_grid) * grid_cell
    transition_weight := clipmap_transition_weight(level, x, z)
    height := terrain.sample_clipmap_transition_height(&editor.project, level, world_x, world_z, transition_weight)
    color, cliff_weight, normal := clipmap_vertex_color(editor, level, world_x, world_z, height, transition_weight)
    vertex := world_vertex({world_x, height, world_z}, color)
    vertex.kind = .Terrain
    vertex.normal = {normal.x, normal.y, normal.z}
    // Terrain vertices otherwise leave material.x unused. Preserve whether
    // this clipmap sample is grass so the world shader can carry the field's
    // traveling wind sheen across the ground beneath the individual cards.
    // Interpolation naturally softens the effect at painted material edges.
    terrain_material := terrain.sample_render_material(&editor.project, level, world_x, world_z)
    grass_weight: f32 = terrain.ground_surface_at(&editor.project, level, world_x, world_z) == .Grass ? 1 : 0
    vertex.material[0] = grass_weight * (1 - cliff_weight)
    // Negative material values identify the generated coastal sand continuum.
    // Carry that broad mask to fragments so fine dune mottling no longer has
    // to be quantized into vertex colors.
    if terrain_material < 0 && cliff_weight < .08 do vertex.material[0] = terrain_material
    // The fragment shader uses the same interpolated slope mask for stable
    // horizontal bedding and weathering on the exposed rock.
    vertex.material[1] = cliff_weight
    vertices[z * resolution + x] = vertex
}

clipmap_update_level :: proc(
    editor: ^Editor,
    vertices: []World_Vertex,
    level: int,
    center: [2]f32,
    dirty: ^Terrain_Dirty_Bounds = nil,
) -> int {
    data := &editor.project.levels[level]
    grid_cell := clipmap_grid_cell(editor, level)
    resolution := clipmap_grid_resolution(level)
    half_grid := f32(resolution - 1) * .5
    min_x, min_z := 0, 0
    max_x, max_z := resolution - 1, resolution - 1
    if dirty != nil {
        padding := data.cell_size * 2
        grid_min_x := center[0] - half_grid * grid_cell
        grid_min_z := center[1] - half_grid * grid_cell
        grid_max_x := center[0] + half_grid * grid_cell
        grid_max_z := center[1] + half_grid * grid_cell
        if dirty.max_x + padding < grid_min_x ||
           dirty.max_z + padding < grid_min_z ||
           dirty.min_x - padding > grid_max_x ||
           dirty.min_z - padding > grid_max_z {
            return 0
        }
        min_x = clamp(int(math.floor(f64((dirty.min_x - padding - grid_min_x) / grid_cell))), 0, resolution - 1)
        min_z = clamp(int(math.floor(f64((dirty.min_z - padding - grid_min_z) / grid_cell))), 0, resolution - 1)
        max_x = clamp(int(math.ceil(f64((dirty.max_x + padding - grid_min_x) / grid_cell))), 0, resolution - 1)
        max_z = clamp(int(math.ceil(f64((dirty.max_z + padding - grid_min_z) / grid_cell))), 0, resolution - 1)
    }
    generated := 0
    for z in min_z ..= max_z {
        for x in min_x ..= max_x {
            clipmap_update_vertex(editor, vertices, level, center, x, z)
            generated += 1
        }
    }
    return generated
}

clipmap_shift_level :: proc(editor: ^Editor, level: int, old_center, new_center: [2]f32) -> (bool, int, int) {
    grid_cell := clipmap_grid_cell(editor, level)
    resolution := clipmap_grid_resolution(level)
    offset, valid := clipmap_center_offset(old_center, new_center, grid_cell, resolution)
    if !valid do return false, 0, 0

    vertex_count := resolution * resolution
    if len(world_renderer.clipmap_scratch_vertex[level]) != vertex_count {
        resize(&world_renderer.clipmap_scratch_vertex[level], vertex_count)
    }
    cache := world_renderer.clipmap_cache_vertex[level][:]
    scratch := world_renderer.clipmap_scratch_vertex[level][:]
    copied, generated := 0, 0
    for z in 0 ..< resolution {
        for x in 0 ..< resolution {
            destination := z * resolution + x
            source, retained := clipmap_shift_source_for_resolution(x, z, offset, resolution)
            source_x, source_z := x + offset[0], z + offset[1]
            morph_unchanged :=
                retained &&
                clipmap_transition_weight(level, x, z) == clipmap_transition_weight(level, source_x, source_z)
            if morph_unchanged {
                scratch[destination] = cache[source]
                copied += 1
            } else {
                clipmap_update_vertex(editor, scratch, level, new_center, x, z)
                generated += 1
            }
        }
    }
    world_renderer.clipmap_cache_vertex[level], world_renderer.clipmap_scratch_vertex[level] =
        world_renderer.clipmap_scratch_vertex[level], world_renderer.clipmap_cache_vertex[level]
    return true, copied, generated
}

@(no_instrumentation)
world_terrain_structure_intersects :: #force_inline proc(
    structure: terrain.Structure,
    dirty: Terrain_Dirty_Bounds,
) -> bool {
    closest_x := clamp(structure.center_x, dirty.min_x, dirty.max_x)
    closest_z := clamp(structure.center_z, dirty.min_z, dirty.max_z)
    dx, dz := structure.center_x - closest_x, structure.center_z - closest_z
    radius_squared := (structure.width * structure.width + structure.depth * structure.depth) * .25
    return dx * dx + dz * dz <= radius_squared
}
