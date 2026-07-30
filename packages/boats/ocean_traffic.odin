package boats

import "core:math"

// Large ocean traffic is transient scenery rather than fixture-backed harbor
// traffic. Dimensions and speeds are authored at the same one-unit-per-metre
// scale as the rest of the world.
Ocean_Class :: enum u8 {
    Product_Tanker,
    Cruise_Ship,
}

Ocean_Specifications :: struct {
    length:           f32,
    beam:             f32,
    draft:            f32,
    height:           f32,
    cruise_speed_mps: f32,
}

ocean_specifications :: proc(class: Ocean_Class) -> Ocean_Specifications {
    switch class {
    case .Product_Tanker:
        // STENA PARIS: 182.9 m LOA, 40 m beam, 11.3 m design draught,
        // 17.9 m moulded depth, and 14.5 knots service speed. Height includes
        // the aft accommodation and bridge above the documented main deck.
        return {182.90, 40.00, 11.30, 32.0, 7.46}
    case .Cruise_Ship:
        // Norwegian Pearl: 294.13 m LOA, 32.2 m beam, 8.3 m draught,
        // 15 decks, and 25 knots service speed.
        return {294.13, 32.20, 8.30, 48.0, 12.86}
    }
    return {}
}

Ocean_Agent :: struct {
    class:         Ocean_Class,
    position:      Vec2,
    yaw:           f32,
    active:        bool,
    wake:          [OCEAN_WAKE_CAPACITY]Wake_Sample,
    wake_count:    int,
    wake_distance: f32,
}

Ocean_Traffic :: struct {
    agent:             Ocean_Agent,
    next_class:        Ocean_Class,
    seconds_until_ship: f32,
    passages:          u32,
}

OCEAN_ROUTE_HALF_EXTENT :: f32(4600)
OCEAN_WAKE_CAPACITY :: 96

new_ocean_traffic :: proc() -> Ocean_Traffic {
    // Let the player settle into the world before the first distant passage.
    return {
        next_class         = .Product_Tanker,
        seconds_until_ship = 90,
    }
}

ocean_traffic_step :: proc(traffic: ^Ocean_Traffic, delta_seconds: f32) {
    if traffic == nil do return
    dt := clamp(delta_seconds, 0, .1)
    if dt <= 0 do return

    if !traffic.agent.active {
        traffic.seconds_until_ship -= dt
        if traffic.seconds_until_ship > 0 do return
        direction := traffic.passages % 2 == 0 ? f32(1) : f32(-1)
        traffic.agent = {
            class    = traffic.next_class,
            position = {-direction * OCEAN_ROUTE_HALF_EXTENT, 0},
            yaw      = direction > 0 ? math.PI * .5 : -math.PI * .5,
            active   = true,
        }
        return
    }

    spec := ocean_specifications(traffic.agent.class)
    direction := traffic.agent.yaw > 0 ? f32(1) : f32(-1)
    distance := spec.cruise_speed_mps * dt
    traffic.agent.position.x += direction * distance
    ocean_wake_step(&traffic.agent, distance, dt)
    if abs(traffic.agent.position.x) <= OCEAN_ROUTE_HALF_EXTENT do return

    traffic.agent.active = false
    traffic.passages += 1
    traffic.next_class =
        traffic.agent.class == .Product_Tanker ? .Cruise_Ship : .Product_Tanker
    // A deterministic 4–7 minute clear horizon separates passages.
    traffic.seconds_until_ship = 240 + f32(traffic.passages % 4) * 60
}

ocean_wake_step :: proc(agent: ^Ocean_Agent, distance_travelled, dt: f32) {
    if agent == nil do return
    write := 0
    for read in 0 ..< agent.wake_count {
        sample := agent.wake[read]
        sample.age += dt
        if sample.age >= sample.lifetime do continue
        agent.wake[write] = sample
        write += 1
    }
    agent.wake_count = write

    spec := ocean_specifications(agent.class)
    agent.wake_distance += distance_travelled
    spacing := spec.beam * .16
    if agent.wake_distance < spacing do return
    agent.wake_distance -= spacing
    if agent.wake_count >= OCEAN_WAKE_CAPACITY {
        for index in 1 ..< agent.wake_count do agent.wake[index - 1] = agent.wake[index]
        agent.wake_count -= 1
    }
    forward := Vec2{math.sin(agent.yaw), -math.cos(agent.yaw)}
    stern := agent.position - forward * (spec.length * .46)
    agent.wake[agent.wake_count] = {
        position  = stern,
        direction = forward,
        lifetime  = agent.class == .Product_Tanker ? f32(82) : f32(68),
        width     = spec.beam,
        strength  = agent.class == .Product_Tanker ? f32(.82) : f32(.68),
    }
    agent.wake_count += 1
}

ocean_tanker_mesh :: proc() -> Mesh {
    result: Mesh
    spec := ocean_specifications(.Product_Tanker)
    hull(
        &result,
        {spec.length, spec.beam, spec.draft, spec.height, spec.cruise_speed_mps, 65_200_000, 15_720},
        6.60,
    )
    // Low cargo deck, raised pipelines, aft accommodation, bridge, and funnel.
    box(&result, {0, 7.0, -8}, {35.0, .55, 118.0}, .Deck)
    box(&result, {0, 8.0, -78}, {26.0, 1.2, 18.0}, .Deck)
    pipeline_x := [3]f32{-10, 0, 10}
    for x in pipeline_x {
        box(&result, {x, 7.65, -8}, {.55, .55, 116.0}, .Metal)
    }
    manifold_z := [5]f32{-54, -27, 0, 27, 50}
    for z in manifold_z {
        box(&result, {0, 8.25, z}, {33.0, 1.1, .75}, .Metal)
    }
    box(&result, {0, 13.0, 68}, {30.0, 12.0, 25.0}, .Cabin)
    box(&result, {0, 20.6, 65}, {27.0, 3.2, 13.0}, .Cabin)
    box(&result, {0, 21.2, 58.4}, {25.0, 1.45, .25}, .Glass)
    box(&result, {8.0, 27.0, 74}, {5.4, 12.0, 6.0}, .Accent)
    box(&result, {0, 15.0, -30}, {.8, 14.0, .8}, .Metal)
    box(&result, {0, 21.5, -30}, {15.0, .6, .6}, .Metal)
    return result
}

ocean_cruise_mesh :: proc() -> Mesh {
    result: Mesh
    spec := ocean_specifications(.Cruise_Ship)
    hull(
        &result,
        {spec.length, spec.beam, spec.draft, spec.height, spec.cruise_speed_mps, 93_500_000, 72_000},
        7.8,
    )
    // The stepped hotel block stops short of the bow and stern, preserving
    // the recognizable long forecastle and terraced aft silhouette.
    box(&result, {0, 16.0, 5}, {28.5, 16.0, 224.0}, .Cabin)
    box(&result, {0, 28.0, 12}, {27.0, 8.0, 202.0}, .Cabin)
    box(&result, {0, 35.0, 17}, {24.0, 6.0, 170.0}, .Cabin)
    window_deck_y := [6]f32{12, 16, 20, 24, 28, 32}
    for y in window_deck_y {
        box(&result, {-14.35, y, 2}, {.20, .55, 205.0}, .Glass)
        box(&result, {14.35, y, 2}, {.20, .55, 205.0}, .Glass)
    }
    box(&result, {0, 39.0, -43}, {15.0, 8.0, 24.0}, .Accent)
    box(&result, {0, 43.5, -43}, {12.0, 1.0, 20.0}, .Metal)
    box(&result, {0, 29.0, -96}, {28.0, 4.0, 13.0}, .Glass)
    lifeboat_z := [7]f32{-66, -44, -22, 0, 22, 44, 66}
    for z in lifeboat_z {
        box(&result, {-15.0, 16.0, z}, {2.2, 2.3, 10.0}, .Accent)
        box(&result, {15.0, 16.0, z}, {2.2, 2.3, 10.0}, .Accent)
    }
    box(&result, {0, 39.0, 44}, {15.0, 1.0, 34.0}, .Deck)
    return result
}

ocean_mesh_cache: [len(Ocean_Class)]Mesh
ocean_mesh_cache_ready: [len(Ocean_Class)]bool

ocean_mesh :: proc(class: Ocean_Class) -> ^Mesh {
    index := int(class)
    if index < 0 || index >= len(ocean_mesh_cache) do return nil
    if !ocean_mesh_cache_ready[index] {
        switch class {
        case .Product_Tanker:
            ocean_mesh_cache[index] = ocean_tanker_mesh()
        case .Cruise_Ship:
            ocean_mesh_cache[index] = ocean_cruise_mesh()
        }
        ocean_mesh_cache_ready[index] = true
    }
    return &ocean_mesh_cache[index]
}
