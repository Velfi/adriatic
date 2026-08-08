package plants

import plant_structure "../plant_structure"
import "core:math"

generated_organ_attachment_kind :: #force_inline proc(kind: Architecture_Organ) -> Attachment_Kind {
    switch kind {
    case .Flower:
        return .Flower
    case .Fruit:
        return .Fruit
    case .Thorn:
        return .Thorn
    case .Tendril:
        return .Tendril
    case .Leaf, .Cladode, .Rosette_Leaf, .Cactus_Rib:
        return .Leaf
    }
    return .Leaf
}

generate :: proc(config: Generate_Config) -> Generate_Result {
    result: Generate_Result
    workspace := generation_active_workspace
    if int(config.species) < 0 || int(config.species) >= SPECIES_COUNT {
        result.error = .Invalid_Species
        return result
    }

    habit := config.habit
    if habit == .Free_Standing &&
       (config.species == .Bougainvillea ||
               config.species == .Grapevine ||
               config.species == .Wisteria ||
               config.species == .Climbing_Rose ||
               config.species == .Star_Jasmine) {
        habit = default_habit(config.species)
    }
    climbing := habit != .Free_Standing
    if climbing && (config.support == nil || config.support.width <= 0 || config.support.height <= 0) {
        result.error = .Invalid_Support
        return result
    }

    maturity := clamp(config.maturity, f32(0), f32(1))
    profile := profile_for(config.species)
    segment_limit, attachment_limit := limits(config.detail)
    if climbing do segment_limit, attachment_limit = climbing_density_limits(config.detail, config.support)

    graph, architecture_error := generate_architecture_stage(config, maturity)
    defer {
        generation_workspace_recycle_unadopted_graph(workspace, &graph)
        destroy_graph(&graph)
    }
    if architecture_error != .None {
        result.error = architecture_error
        return result
    }
    if len(graph.internodes) > segment_limit {
        result.error = .Segment_Limit
        return result
    }
    if len(graph.organs) > attachment_limit {
        result.error = .Attachment_Limit
        return result
    }

    plant := &result.plant
    plant.species = config.species
    plant.habit = habit
    plant.maturity = maturity
    plant.root_kind = climbing && config.support.planter ? .Planter : .Soil
    plant.wind_compliance = woody_wind_compliance(config.species, maturity)
    if climbing do plant.support_signature = support_hash(config.support^)
    #partial switch config.species {
    case .Olive:
        plant.wood = {
            radial_irregularity = .20,
            twist               = 1.50,
        }
    case .Italian_Cypress:
        plant.wood = {
            radial_irregularity = .075,
            twist               = .42,
        }
    case .Lemon:
        plant.wood = {
            radial_irregularity = .055,
            twist               = .28,
        }
    }

    generation_workspace_output_take(plant)
    _ = non_zero_reserve(&plant.segments, len(graph.internodes))
    _ = non_zero_reserve(&plant.attachments, len(graph.organs))

    climbing_height, climbing_half_width := f32(.001), f32(.001)
    if climbing {
        for internode in graph.internodes {
            start := plant_structure.Vec3 {
                internode.start[0] * profile.width_scale,
                internode.start[1] * profile.height_scale,
                internode.start[2] * profile.width_scale,
            }
            end := plant_structure.Vec3 {
                internode.end[0] * profile.width_scale,
                internode.end[1] * profile.height_scale,
                internode.end[2] * profile.width_scale,
            }
            climbing_height = max(climbing_height, max(start[1], end[1]))
            climbing_half_width = max(
                climbing_half_width,
                max(max(math.abs(start[0]), math.abs(end[0])), max(math.abs(start[2]), math.abs(end[2]))),
            )
        }
    }

    first := true
    for internode in graph.internodes {
        segment := plant_structure.Segment {
            start        = {
                internode.start[0] * profile.width_scale,
                internode.start[1] * profile.height_scale,
                internode.start[2] * profile.width_scale,
            },
            end          = {
                internode.end[0] * profile.width_scale,
                internode.end[1] * profile.height_scale,
                internode.end[2] * profile.width_scale,
            },
            radius_start = internode.radius_start,
            radius_end   = internode.radius_end,
            depth        = internode.render_depth,
        }
        if climbing {
            segment.start = route_species_point(
                segment.start,
                config.support,
                climbing_height,
                climbing_half_width,
                habit,
                segment.depth,
                config.species,
            )
            segment.end = route_species_point(
                segment.end,
                config.support,
                climbing_height,
                climbing_half_width,
                habit,
                segment.depth,
                config.species,
            )
        }
        append(&plant.segments, segment)
        update_bounds(&plant.bounds, segment.start, &first)
        update_bounds(&plant.bounds, segment.end, &first)
    }

    for organ, organ_index in graph.organs {
        if organ.internode < 0 || organ.internode >= len(graph.internodes) {
            destroy(&result)
            result.error = .Interpretation_Failed
            return result
        }
        internode := graph.internodes[organ.internode]
        fraction := clamp(organ.fraction, f32(0), f32(1))
        source_position := internode.start + (internode.end - internode.start) * fraction
        position := plant_structure.Vec3 {
            source_position[0] * profile.width_scale,
            source_position[1] * profile.height_scale,
            source_position[2] * profile.width_scale,
        }
        if climbing {
            position = route_species_point(
                position,
                config.support,
                climbing_height,
                climbing_half_width,
                habit,
                organ.render_depth,
                config.species,
            )
        }
        kind := generated_organ_attachment_kind(organ.kind)
        forward, up := attachment_frame(organ.forward, organ.up, profile, climbing)
        if climbing do fold_source_attachment_frame(&forward, &up, position, config.support)
        traits :=
            kind == .Leaf ? generated_leaf_traits(config.species, organ.variant, maturity, config.detail) : Leaf_Traits{}
        if kind == .Leaf {
            depth_scale := f32(1)
            #partial switch config.species {
            case .Agave:
                if organ.render_depth == 1 do depth_scale = .68
            case .Aloe:
                if organ.render_depth == 1 do depth_scale = .70
                if organ.render_depth >= 2 do depth_scale = .74
            case .Echeveria:
                if organ.render_depth == 1 do depth_scale = .66
                if organ.render_depth >= 2 do depth_scale = .72
            case .Golden_Barrel, .Aeonium, .Jade_Plant, .Stonecrop, .Blue_Chalk_Sticks, .Golden_Torch_Cactus:
            }
            traits.length *= depth_scale
            traits.width *= .84 + depth_scale * .16
        }
        append(&plant.attachments, Attachment {
            kind     = kind,
            stage    = attachment_stage(kind, config.seed, organ_index, maturity),
            position = position,
            forward  = forward,
            up       = up,
            depth    = organ.render_depth,
            variant  = organ.variant,
            leaf     = traits,
        })
        update_bounds(&plant.bounds, position, &first)
        if kind == .Leaf do update_leaf_bounds(&plant.bounds, position, forward, up, traits, &first)
    }

    if !generated_graph_adopt_native(plant, &graph, profile) {
        destroy(&result)
        result.error = .Interpretation_Failed
        return result
    }
    generation_workspace_commit(workspace, plant)
    return result
}
