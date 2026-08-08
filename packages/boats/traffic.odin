package boats

import "core:math"
import "core:math/linalg"

TRAFFIC_CAPACITY :: 32
DEFAULT_TRAFFIC_COUNT :: 4
ROUTE_CAPACITY :: 8
SCHEDULE_CAPACITY :: 5
WAKE_CAPACITY :: 48

Vec2 :: [2]f32

Behavior :: enum u8 {
    Transit,
    Patrol,
    Loiter,
    Moored,
}

Schedule_Entry :: struct {
    start_minutes: f32,
    end_minutes:   f32,
    behavior:      Behavior,
    speed_scale:   f32,
}

Wake_Sample :: struct {
    position:  Vec2,
    direction: Vec2,
    age:       f32,
    lifetime:  f32,
    width:     f32,
    strength:  f32,
}

Agent :: struct {
    class:            Class,
    position:         Vec2,
    velocity:         Vec2,
    yaw:              f32,
    speed:            f32,
    throttle:         f32,
    behavior:         Behavior,
    route:            [ROUTE_CAPACITY]Vec2,
    route_count:      int,
    route_index:      int,
    schedule:         [SCHEDULE_CAPACITY]Schedule_Entry,
    schedule_count:   int,
    loiter_center:    Vec2,
    loiter_radius:    f32,
    loiter_phase:     f32,
    mooring_position: Vec2,
    mooring_yaw:      f32,
    wake:             [WAKE_CAPACITY]Wake_Sample,
    wake_count:       int,
    wake_distance:    f32,
}

Traffic :: struct {
    agents: [TRAFFIC_CAPACITY]Agent,
    count:  int,
    clock:  f32,
}

@(no_instrumentation)
agent_forward :: #force_inline proc(agent: Agent) -> Vec2 {
    return {math.sin(agent.yaw), -math.cos(agent.yaw)}
}

schedule_behavior :: proc(agent: ^Agent, world_minutes: f32) -> (Behavior, f32) {
    if agent == nil || agent.schedule_count <= 0 do return .Patrol, 1
    phase := world_minutes - f32(math.floor(f64(world_minutes / 1440))) * 1440
    if phase < 0 do phase += 1440
    for entry in agent.schedule[:agent.schedule_count] {
        if phase >= entry.start_minutes && phase < entry.end_minutes {
            return entry.behavior, entry.speed_scale
        }
    }
    return agent.schedule[agent.schedule_count - 1].behavior, agent.schedule[agent.schedule_count - 1].speed_scale
}

wake_strength :: proc(class: Class, speed: f32) -> f32 {
    spec := specifications(class)
    if speed <= .15 || spec.cruise_speed_mps <= 0 do return 0
    speed_ratio := clamp(speed / spec.cruise_speed_mps, 0, 1.35)
    tonnes := max(spec.displacement_kg / 1000, f32(.1))
    power_loading := clamp(spec.engine_power_kw / tonnes / 120, 0, 1)
    displacement := clamp(f32(math.sqrt(f64(tonnes / 12))), 0, 1)
    return clamp(f32(math.pow(f64(speed_ratio), 1.35)) * (.30 + power_loading * .36 + displacement * .34), 0, 1)
}

agent_schedule :: proc(class: Class) -> [SCHEDULE_CAPACITY]Schedule_Entry {
    // Entries use the same 0..1440 world-minute clock displayed in the HUD.
    switch class {
    case .Dinghy:
        return {
            {0, 390, .Loiter, .05},
            {390, 720, .Patrol, .65},
            {720, 780, .Loiter, .10},
            {780, 1140, .Transit, .78},
            {1140, 1440, .Loiter, .05},
        }
    case .Motor:
        return {
            {0, 390, .Loiter, .08},
            {390, 720, .Patrol, .78},
            {720, 780, .Loiter, .14},
            {780, 1140, .Transit, 1},
            {1140, 1440, .Loiter, .08},
        }
    case .Sail:
        return {
            {0, 480, .Loiter, .05},
            {480, 900, .Patrol, .82},
            {900, 960, .Loiter, .12},
            {960, 1200, .Transit, .92},
            {1200, 1440, .Loiter, .05},
        }
    case .Fishing:
        return {
            {0, 270, .Transit, .88},
            {270, 660, .Patrol, .72},
            {660, 780, .Transit, 1},
            {780, 1320, .Loiter, .10},
            {1320, 1440, .Transit, .82},
        }
    case .Tug:
        return {
            {0, 360, .Loiter, .08},
            {360, 600, .Patrol, .66},
            {600, 1080, .Transit, .92},
            {1080, 1260, .Patrol, .70},
            {1260, 1440, .Loiter, .08},
        }
    }
    return {}
}

new_traffic :: proc() -> Traffic {
    traffic: Traffic
    classes := [DEFAULT_TRAFFIC_COUNT]Class{.Motor, .Sail, .Fishing, .Tug}
    centers := [DEFAULT_TRAFFIC_COUNT]Vec2{{1740, 1220}, {1020, 1740}, {-1740, -1220}, {-1020, -1740}}
    route_radii := [DEFAULT_TRAFFIC_COUNT]f32{105, 82, 66, 54}
    for class, index in classes {
        center := centers[index]
        radius := route_radii[index]
        schedule := agent_schedule(class)
        agent := &traffic.agents[index]
        agent.class = class
        agent.position = {center.x + radius, center.y}
        agent.yaw = math.PI * .5
        agent.loiter_center = center
        agent.loiter_radius = radius * .34
        agent.loiter_phase = f32(index) * 1.3
        agent.schedule = schedule
        agent.schedule_count = len(schedule)
        agent.route_count = 6
        for route_index in 0 ..< agent.route_count {
            angle := f32(route_index) * math.PI * 2 / f32(agent.route_count) + f32(index) * .31
            agent.route[route_index] = {center.x + math.cos(angle) * radius, center.y + math.sin(angle) * radius * .72}
        }
    }
    traffic.count = len(classes)
    return traffic
}

append_agent :: proc(traffic: ^Traffic, agent: Agent) -> ^Agent {
    if traffic == nil || traffic.count >= TRAFFIC_CAPACITY do return nil
    traffic.agents[traffic.count] = agent
    result := &traffic.agents[traffic.count]
    traffic.count += 1
    return result
}

add_moored_agent :: proc(traffic: ^Traffic, class: Class, position: Vec2, yaw: f32) -> ^Agent {
    return append_agent(traffic, {
        class            = class,
        position         = position,
        yaw              = yaw,
        behavior         = .Moored,
        mooring_position = position,
        mooring_yaw      = yaw,
    })
}

agent_target :: proc(agent: ^Agent, dt: f32) -> Vec2 {
    if agent.behavior == .Loiter {
        rate := .12 + specifications(agent.class).cruise_speed_mps * .008
        agent.loiter_phase += dt * rate
        return {
            agent.loiter_center.x + math.cos(agent.loiter_phase) * agent.loiter_radius,
            agent.loiter_center.y + math.sin(agent.loiter_phase) * agent.loiter_radius,
        }
    }
    target := agent.route[agent.route_index]
    threshold := max(specifications(agent.class).length * .75, f32(8))
    if linalg.length(target - agent.position) < threshold {
        if agent.behavior == .Patrol {
            agent.route_index = (agent.route_index + 1) % agent.route_count
        } else {
            agent.route_index = (agent.route_index + 2) % agent.route_count
        }
        target = agent.route[agent.route_index]
    }
    return target
}

avoidance_vector :: proc(traffic: ^Traffic, agent_index: int) -> Vec2 {
    agent := &traffic.agents[agent_index]
    result: Vec2
    for other, other_index in traffic.agents[:traffic.count] {
        if other_index == agent_index do continue
        separation := agent.position - other.position
        distance := linalg.length(separation)
        safe_distance := (specifications(agent.class).length + specifications(other.class).length) * .65 + 8
        if distance <= .001 || distance >= safe_distance do continue
        closing := linalg.dot(agent.velocity - other.velocity, linalg.normalize0(separation))
        urgency := (1 - distance / safe_distance) * (closing < 0 ? f32(1.35) : f32(.72))
        result += linalg.normalize0(separation) * urgency
    }
    return result
}

wake_step :: proc(agent: ^Agent, distance_travelled, dt: f32) {
    write := 0
    for read in 0 ..< agent.wake_count {
        sample := agent.wake[read]
        sample.age += dt
        if sample.age >= sample.lifetime do continue
        agent.wake[write] = sample
        write += 1
    }
    agent.wake_count = write

    strength := wake_strength(agent.class, agent.speed)
    if strength <= .015 do return
    agent.wake_distance += distance_travelled
    spacing := max(specifications(agent.class).beam * .28, f32(.65))
    if agent.wake_distance < spacing do return
    agent.wake_distance -= spacing
    if agent.wake_count >= WAKE_CAPACITY {
        for index in 1 ..< agent.wake_count do agent.wake[index - 1] = agent.wake[index]
        agent.wake_count -= 1
    }
    spec := specifications(agent.class)
    forward := agent_forward(agent^)
    stern := agent.position - forward * (spec.length * .43)
    tonnes := spec.displacement_kg / 1000
    lifetime := 4.2 + clamp(f32(math.sqrt(f64(tonnes))), 1, 7) * .48
    agent.wake[agent.wake_count] = {
        position  = stern,
        direction = forward,
        lifetime  = lifetime,
        width     = spec.beam * (.42 + strength * .48),
        strength  = strength,
    }
    agent.wake_count += 1
}

step :: proc(traffic: ^Traffic, delta_seconds, world_minutes: f32) {
    if traffic == nil do return
    dt := clamp(delta_seconds, 0, .05)
    if dt <= 0 do return
    traffic.clock += dt
    for index in 0 ..< traffic.count {
        agent := &traffic.agents[index]
        if agent.behavior == .Moored {
            agent.position = agent.mooring_position
            agent.velocity = {}
            agent.yaw = agent.mooring_yaw
            agent.speed = 0
            agent.throttle = 0
            agent.wake_count = 0
            agent.wake_distance = 0
            continue
        }
        behavior, schedule_speed := schedule_behavior(agent, world_minutes)
        agent.behavior = behavior
        target := agent_target(agent, dt)
        desired := linalg.normalize0(target - agent.position)
        avoidance := avoidance_vector(traffic, index)
        desired = linalg.normalize0(desired + avoidance * 2.6)

        spec := specifications(agent.class)
        target_speed := spec.cruise_speed_mps * schedule_speed
        if linalg.length(avoidance) > .2 do target_speed *= clamp(1 - linalg.length(avoidance) * .45, .25, 1)
        acceleration := agent.class == .Tug ? f32(.42) : f32(1.25)
        agent.speed += clamp(target_speed - agent.speed, -acceleration * dt, acceleration * dt)
        agent.throttle = target_speed > .01 ? clamp(agent.speed / target_speed, 0, 1) : 0

        desired_yaw := math.atan2(desired.x, -desired.y)
        yaw_delta := desired_yaw - agent.yaw
        for yaw_delta > math.PI do yaw_delta -= math.PI * 2
        for yaw_delta < -math.PI do yaw_delta += math.PI * 2
        turn_rate := agent.class == .Tug ? f32(.22) : f32(.55)
        agent.yaw += clamp(yaw_delta, -turn_rate * dt, turn_rate * dt)
        forward := agent_forward(agent^)
        agent.velocity = forward * agent.speed
        distance := agent.speed * dt
        agent.position += agent.velocity * dt
        wake_step(agent, distance, dt)
    }
}
