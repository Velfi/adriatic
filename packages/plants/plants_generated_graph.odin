package plants

import plant_structure "../plant_structure"
import "core:math"
import "core:math/linalg"

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

generated_stable_id :: #force_inline proc(seed: u64, domain: u64, index: int) -> u64 {
    state := seed ~ domain ~ (u64(index) + 1) * 0x9e3779b97f4a7c15
    return plant_structure.random_next(&state)
}

olive_random_signed :: proc(random: ^u64) -> f32 {
    return f32(plant_structure.random_next(random) >> 40) / f32(1 << 24) * 2 - 1
}

generated_graph_organ_kind :: #force_inline proc(kind: Attachment_Kind) -> Architecture_Organ {
    switch kind {
    case .Leaf:
        return .Leaf
    case .Flower:
        return .Flower
    case .Fruit:
        return .Fruit
    case .Thorn:
        return .Thorn
    case .Tendril:
        return .Tendril
    }
    return .Leaf
}

generated_graph_nearest_internode :: proc(graph: ^Plant_Graph, position: plant_structure.Vec3) -> (int, f32) {
    nearest := -1
    nearest_fraction := f32(0)
    nearest_distance := f32(math.F32_MAX)
    for internode, index in graph.internodes {
        direction := internode.end - internode.start
        length_squared := linalg.dot(direction, direction)
        fraction := f32(0)
        if length_squared > 1e-10 {
            fraction = clamp(linalg.dot(position - internode.start, direction) / length_squared, f32(0), f32(1))
        }
        delta := position - (internode.start + direction * fraction)
        distance := linalg.dot(delta, delta)
        if distance < nearest_distance {
            nearest = index
            nearest_fraction = fraction
            nearest_distance = distance
        }
    }
    return nearest, nearest_fraction
}

generated_graph_build :: proc(plant: ^Generated_Plant, seed: u64) {
    if plant == nil do return
    destroy_graph(&plant.graph)
    axis_count := len(plant.axis_parents)
    axis_units := make([]int, axis_count)
    defer delete(axis_units)
    axis_parent_internodes := make([]int, axis_count)
    defer delete(axis_parent_internodes)
    for &value in axis_parent_internodes do value = -1
    for segment_index in 0 ..< len(plant.segments) {
        axis := plant.segment_axes[segment_index]
        parent := plant.segment_parents[segment_index]
        if parent >= 0 && plant.segment_axes[parent] != axis && axis_parent_internodes[axis] < 0 {
            axis_parent_internodes[axis] = parent
        }
    }
    for axis in 0 ..< axis_count {
        order := u8(0)
        parent := plant.axis_parents[axis]
        for parent >= 0 {
            order += 1
            parent = plant.axis_parents[parent]
        }
        axis_index := graph_add_axis(
            &plant.graph,
            plant.axis_parents[axis],
            axis_parent_internodes[axis],
            plant.axis_roles[axis],
            plant.axis_orientations[axis],
            order,
            max(1 - f32(order) * .18, f32(.12)),
            plant.maturity,
        )
        plant.graph.axes[axis_index].stable_id = generated_stable_id(seed, 0x41584953, axis)
        axis_units[axis] = graph_begin_growth_unit(&plant.graph, axis, f32(axis) * 2.399963, plant.maturity)
        plant.graph.growth_units[axis_units[axis]].stable_id = generated_stable_id(seed, 0x47524f575448, axis)
    }
    for segment, segment_index in plant.segments {
        internode := graph_add_internode(
            &plant.graph,
            plant.segment_axes[segment_index],
            axis_units[plant.segment_axes[segment_index]],
            plant.segment_parents[segment_index],
            segment.start,
            segment.end,
            segment.radius_start,
            segment.radius_end,
            plant.maturity,
            segment.depth,
        )
        plant.graph.internodes[internode].stable_id = plant.segment_ids[segment_index]
    }
    terminal := make([]int, axis_count)
    defer delete(terminal)
    for &value in terminal do value = -1
    for internode, index in plant.graph.internodes do terminal[internode.axis] = index
    for internode, axis in terminal {
        if internode < 0 do continue
        append(
            &plant.graph.buds,
            Bud {
                internode = internode,
                state = plant.maturity < 1 ? Bud_State.Continuing : .Terminated,
                vigor = plant.graph.axes[axis].vigor,
                stable_id = generated_stable_id(seed, 0x425544, axis),
            },
        )
    }
    for attachment, attachment_index in plant.attachments {
        internode, fraction := generated_graph_nearest_internode(&plant.graph, attachment.position)
        if internode < 0 do continue
        append(
            &plant.graph.organs,
            Organ_Site {
                internode = internode,
                fraction = fraction,
                kind = generated_graph_organ_kind(attachment.kind),
                forward = attachment.forward,
                up = attachment.up,
                variant = attachment.variant,
                render_depth = plant.graph.internodes[internode].render_depth,
                stable_id = plant.attachment_ids[attachment_index],
            },
        )
    }
}

// Preserve the authored botanical topology after the ordinary generation
// stage has applied species scale and compiled render attachments. Native
// graphs and their flattened segment/organ streams are deliberately emitted
// in the same stable order, so no geometry-dependent reconstruction is
// needed for graph-authored species.
generated_graph_adopt_native :: proc(plant: ^Generated_Plant, graph: ^Plant_Graph, profile: Profile) -> bool {
    if plant == nil || graph == nil do return false
    if len(graph.internodes) != len(plant.segments) || len(graph.organs) != len(plant.attachments) do return false

    clear(&plant.segment_parents)
    clear(&plant.segment_axes)
    clear(&plant.segment_ids)
    clear(&plant.axis_parents)
    clear(&plant.axis_roles)
    clear(&plant.axis_orientations)
    clear(&plant.attachment_ids)
    destroy_graph(&plant.graph)

    _ = non_zero_reserve(&plant.segment_parents, len(graph.internodes))
    _ = non_zero_reserve(&plant.segment_axes, len(graph.internodes))
    _ = non_zero_reserve(&plant.segment_ids, len(graph.internodes))
    for &internode, index in graph.internodes {
        internode.start[0] *= profile.width_scale
        internode.start[1] *= profile.height_scale
        internode.start[2] *= profile.width_scale
        internode.end[0] *= profile.width_scale
        internode.end[1] *= profile.height_scale
        internode.end[2] *= profile.width_scale
        internode.age = plant.maturity
        append(&plant.segment_parents, internode.parent)
        append(&plant.segment_axes, internode.axis)
        append(&plant.segment_ids, internode.stable_id)
        // The compiled segment is authoritative after generation policy, but
        // native topology must describe exactly the same render geometry.
        internode.start = plant.segments[index].start
        internode.end = plant.segments[index].end
        internode.radius_start = plant.segments[index].radius_start
        internode.radius_end = plant.segments[index].radius_end
    }

    _ = non_zero_reserve(&plant.axis_parents, len(graph.axes))
    _ = non_zero_reserve(&plant.axis_roles, len(graph.axes))
    _ = non_zero_reserve(&plant.axis_orientations, len(graph.axes))
    for &axis in graph.axes {
        axis.age = plant.maturity
        append(&plant.axis_parents, axis.parent_axis)
        append(&plant.axis_roles, axis.role)
        append(&plant.axis_orientations, axis.orientation)
    }

    _ = non_zero_reserve(&plant.attachment_ids, len(graph.organs))
    for &organ, index in graph.organs {
        attachment := plant.attachments[index]
        if attachment.kind != .Leaf {
            organ.kind = generated_graph_organ_kind(attachment.kind)
        }
        organ.forward = attachment.forward
        organ.up = attachment.up
        organ.variant = attachment.variant
        organ.render_depth = attachment.depth
        append(&plant.attachment_ids, organ.stable_id)
    }

    plant.graph = graph^
    graph^ = {}
    return true
}
