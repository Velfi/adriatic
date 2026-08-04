package plants

generate_architecture_stage :: proc(
    config: Generate_Config,
    maturity: f32,
) -> (Plant_Graph, Generate_Error) {
    graph: Plant_Graph
    switch config.species {
    case .Olive,
         .Fig,
         .Lemon,
         .Pomegranate,
         .Almond,
         .Stone_Pine,
         .Bay_Laurel,
         .Carob,
         .Strawberry_Tree,
         .Myrtle,
         .Mastic,
         .Holm_Oak,
         .Oriental_Plane,
         .European_Hackberry,
         .White_Poplar:
        graph = native_woody_graph(config.species, config.seed, maturity, config.detail)
    case .Italian_Cypress:
        graph = native_cypress_graph(config.seed, maturity, config.detail)
    case .Agapanthus:
        graph = agapanthus_graph(config.seed, maturity, config.detail)
    case .Rosemary, .Lavender, .Thyme, .Sage:
        graph = native_herb_graph(config.species, config.seed, maturity, config.detail)
    case .Pelargonium:
        graph = pelargonium_graph(config.seed, maturity)
    case .Oleander:
        graph = oleander_graph(config.seed, maturity, config.detail)
    case .Hydrangea_Bush, .Hydrangea_Tree:
        graph = hydrangea_graph(config.species, config.seed, maturity, config.detail)
    case .Grapevine, .Bougainvillea, .Star_Jasmine, .Wisteria, .Climbing_Rose:
        graph = native_climber_graph(config.species, config.seed, maturity, config.detail)
    case .Prickly_Pear:
        graph = prickly_pear_graph(config.seed, maturity)
    case .Golden_Barrel, .Agave, .Aloe:
        graph = fleshy_plant_graph(config.species, config.seed, maturity, config.detail)
    case .Aeonium, .Echeveria, .Jade_Plant, .Stonecrop, .Blue_Chalk_Sticks, .Golden_Torch_Cactus:
        graph = succulent_catalog_graph(config.species, config.seed, maturity, config.detail)
    case:
        return {}, .Expansion_Failed
    }
    return graph, .None
}
