package main

import atmosphere "../packages/atmosphere"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:math"
import "core:testing"
import canvas2d "zelda_engine:canvas2d"

// Witch Lab uses metres, seconds, kilograms, and radians. Player intent is
// sampled once per rendered frame; all physical state advances at 120 Hz.
WITCH_FIXED_DT :: f32(1.0 / 120.0)
WITCH_MAX_STEPS :: 8
WITCH_RING_COUNT :: 18
WITCH_RING_RADIUS :: f32(5.6)
WITCH_TERRAIN_COLUMNS :: 36
WITCH_TERRAIN_ROWS :: 36
WITCH_TERRAIN_TILE_X :: f32(12)
WITCH_TERRAIN_TILE_Z :: f32(14)
WITCH_TERRAIN_MIN_X :: f32(-210)
WITCH_TERRAIN_MIN_Z :: f32(-180)

Witch_Rider_State :: enum {Comfortable, Bracing, Straining, Slipping, Critical, Recovering}
Witch_Activity :: enum {Flow_Course, Wind_Crossing, Thermal_Landing}

Witch_Tree :: struct {x, z, scale: f32}

Witch_Broom_Config :: struct {
    broom_mass, rider_mass:                    f32,
    max_support_force, forward_thrust:          f32,
    braking_force:                             f32,
    pitch_torque, roll_torque, yaw_torque:      f32,
    attitude_gain, angular_damping:             f32,
    comfortable_acceleration, max_acceleration: f32,
    linear_drag, lateral_drag:                  f32,
    grip_strength, brace_multiplier:            f32,
    shaft_stiffness, shaft_damping:              f32,
    power_capacity, power_recovery:              f32,
    ground_assist:                              f32,
    cruise_throttle:                            f32,
    lateral_control_speed, vertical_control_speed: f32,
    axis_control_gain, axis_control_acceleration: f32,
    stick_deadzone, camera_stick_deadzone:       f32,
    trigger_deadzone:                           f32,
}

Witch_Intent :: struct {
    steer, climb, throttle, brake: f32,
    orbit_x, orbit_y:              f32,
    brace:                         bool,
}

// Device polling is contained here; simulation and presentation consume this
// action-level snapshot and never need to know which device produced it.
Witch_Input_Frame :: struct {
    intent:                         Witch_Intent,
    reset, replay, recenter:        bool,
    activity_1, activity_2, activity_3: bool,
    activity_previous, activity_next: bool,
    debug_toggle, recovery_demo:    bool,
    toggle_horizontal, toggle_vertical: bool,
    gamepad_active:                 bool,
}

Witch_Landing_Assist :: struct {
    factor: f32,
    lift:   f32,
    drag:   third_person.Vec3,
}

Witch_Pose_Params :: struct {
    lean, crouch:               f32,
    torso_fore_aft:             f32,
    head_fore_aft:              f32,
    strain:                     f32,
}

Witch_Broom_State :: struct {
    position, velocity:           third_person.Vec3,
    yaw, pitch, roll:             f32,
    angular_velocity:             third_person.Vec3,
    desired_acceleration:         third_person.Vec3,
    actual_acceleration:          third_person.Vec3,
    wind, net_force, net_torque:  third_person.Vec3,
    segment_forces:               [3]third_person.Vec3,
    power, grip, shaft_flex:      f32,
    rider_state:                  Witch_Rider_State,
    recovery_time:                f32,
}

Witch_Lab_State :: struct {
    config:                 Witch_Broom_Config,
    broom:                  Witch_Broom_State,
    intent:                 Witch_Intent,
    flight_intent:          Witch_Intent,
    previous_position:      third_person.Vec3,
    previous_attitude:      third_person.Vec3,
    accumulator, last_time: f32,
    camera_yaw, camera_pitch, camera_distance: f32,
    camera_orbit_time:       f32,
    camera_frame_dt:         f32,
    camera_obstruction_offset: third_person.Vec3,
    camera_obstruction_snap: bool,
    activity:               Witch_Activity,
    ring_index:             int,
    ring_pass_time:         f32,
    ring_pass_position:     third_person.Vec3,
    parcel_security:        f32,
    thermal_reached:        bool,
    activity_complete:      bool,
    completion_time:        f32,
    collision_time:         f32,
    landing_assist:         f32,
    gust_warning, gust_side: f32,
    landed:                 bool,
    debug:                  bool,
    controller_used:        bool,
    invert_horizontal, invert_vertical: bool,
    show_course_overview:   bool,
    pose_preview:           int,
}

witch_lab: Witch_Lab_State

witch_trees := [?]Witch_Tree{
    {-48,-49,1.1}, {-29,-35,.9}, {31,-42,1.2}, {51,-20,1},
    {-54,3,1.15}, {49,8,.95}, {-43,42,1.1}, {54,55,1.15},
    {-51,86,1}, {51,97,1.05}, {-38,124,1.2}, {66,139,1},
    // Circuit obstacles form readable slaloms rather than walls. Every tree
    // uses the same proactive avoidance and recoverable collision response.
    {-31,-1,.82}, {-57,23,.95}, {-34,53,1.05}, {-31,76,.9},
    {1,88,1.05}, {27,103,.92}, {47,124,1.08}, {42,145,.88},
    {13,132,.96}, {-17,117,1.02}, {-45,99,.9}, {-50,67,1.08},
    {-35,32,.86}, {-20,9,.92},
}

witch_default_config :: proc() -> Witch_Broom_Config {
    return {
        broom_mass = 8, rider_mass = 48,
        max_support_force = 980, forward_thrust = 620, braking_force = 470,
        pitch_torque = 22, roll_torque = 30, yaw_torque = 58,
        attitude_gain = 8.5, angular_damping = 5.8,
        comfortable_acceleration = 10.5, max_acceleration = 24,
        linear_drag = .075, lateral_drag = .34,
        grip_strength = 1, brace_multiplier = 1.75,
        shaft_stiffness = 18, shaft_damping = 7,
        power_capacity = 100, power_recovery = 8.5,
        ground_assist = 12, cruise_throttle = .42,
        lateral_control_speed = 9.5, vertical_control_speed = 10.5,
        axis_control_gain = 2.15, axis_control_acceleration = 7.5,
        stick_deadzone = .11, camera_stick_deadzone = .19,
        trigger_deadzone = .08,
    }
}

witch_length :: #force_inline proc(v: third_person.Vec3) -> f32 {
    return f32(math.sqrt(f64(v.x*v.x + v.y*v.y + v.z*v.z)))
}

witch_safe_normalize :: #force_inline proc(v: third_person.Vec3, fallback: third_person.Vec3) -> third_person.Vec3 {
    length := witch_length(v)
    if length < .0001 do return fallback
    return v / length
}

witch_approach :: #force_inline proc(current,target,max_delta: f32) -> f32 {
    return current+clamp(target-current,-max_delta,max_delta)
}

witch_angle_delta :: #force_inline proc(target,current: f32) -> f32 {
    return f32(math.atan2(math.sin(f64(target-current)),math.cos(f64(target-current))))
}

witch_propulsion_input :: #force_inline proc(intent: Witch_Intent, cruise_throttle: f32) -> f32 {
    // Star Fox-like handling: neutral controls maintain a stable forward
    // cruise, the right trigger boosts, and brake cancels cruise first.
    cruise := cruise_throttle*(1-intent.brake)
    return clamp(cruise+intent.throttle*(1-cruise_throttle),0,1)
}

witch_forward :: #force_inline proc(yaw, pitch: f32) -> third_person.Vec3 {
    cp := f32(math.cos(f64(pitch)))
    return {f32(math.sin(f64(yaw))) * cp, f32(math.sin(f64(pitch))), -f32(math.cos(f64(yaw))) * cp}
}

witch_right :: #force_inline proc(yaw: f32) -> third_person.Vec3 {
    return {f32(math.cos(f64(yaw))), 0, f32(math.sin(f64(yaw)))}
}

witch_cross :: #force_inline proc(a,b: third_person.Vec3) -> third_person.Vec3 {
    return {a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x}
}

witch_ground_height :: proc(x, z: f32) -> f32 {
    meadow := .35 * f32(math.sin(f64(x * .035))) + .25 * f32(math.sin(f64(z * .05)))
    valley := -3.8 * f32(math.exp(-f64((z - 30) * (z - 30)) / 240))
    ridge := 13 * f32(math.exp(-f64((z - 92) * (z - 92)) / 380))
    return meadow + valley + ridge
}

witch_terrain_lookahead_lift :: proc(position,velocity: third_person.Vec3, descend_intent,strength: f32) -> f32 {
    horizontal := third_person.Vec3{velocity.x,0,velocity.z}
    speed := witch_length(horizontal)
    if speed < 1 do return 0
    direction := horizontal/speed
    lookahead := clamp(speed*1.15,4,20)
    ahead := position+direction*lookahead
    ahead_ground := witch_ground_height(ahead.x,ahead.z)
    future_clearance := position.y-ahead_ground
    if future_clearance >= 5 do return 0
    assistance := (5-future_clearance)*strength*3.4
    // Sustained descend remains authoritative; assistance softens the impact
    // rather than visibly cancelling a deliberate low approach.
    if descend_intent < -.35 do assistance *= .32
    return clamp(assistance,0,260)
}

witch_obstacle_avoidance_acceleration :: proc(position,velocity: third_person.Vec3, steer_intent: f32) -> third_person.Vec3 {
    horizontal := third_person.Vec3{velocity.x,0,velocity.z}
    speed := witch_length(horizontal)
    if speed < 2 do return {}
    direction := horizontal/speed
    result: third_person.Vec3
    for tree in witch_trees {
        ground := witch_ground_height(tree.x,tree.z)
        if position.y > ground+11*tree.scale do continue
        to_tree := third_person.Vec3{tree.x-position.x,0,tree.z-position.z}
        along := to_tree.x*direction.x+to_tree.z*direction.z
        lookahead := clamp(speed*.8,7,16)
        if along <= 0 || along >= lookahead do continue
        closest := to_tree-direction*along
        lateral_distance := witch_length(closest)
        safe_radius := 3.2*tree.scale+2.2
        if lateral_distance >= safe_radius do continue
        away := witch_safe_normalize(closest*-1,witch_right(witch_lab.broom.yaw))
        proximity := (1-lateral_distance/safe_radius)*(1-along/lookahead)
        authority := 1-clamp(math.abs(steer_intent),0,1)*.65
        result += away*proximity*authority*8
    }
    length := witch_length(result)
    if length>6 do result *= 6/length
    return result
}

witch_landing_assistance :: proc(position,velocity: third_person.Vec3, intent: Witch_Intent, mass: f32) -> Witch_Landing_Assist {
    platform_ground := witch_ground_height(42,132)
    dx,dz := math.abs(position.x-42),math.abs(position.z-132)
    if dx>24 || dz>18 do return {}
    altitude := position.y-platform_ground
    if altitude<0 || altitude>9 do return {}
    horizontal_edge := max(dx/24,dz/18)
    factor := (1-clamp(horizontal_edge,0,1))*(1-clamp((altitude-1)/8,0,1))
    // Throttle remains an explicit go-around command.
    factor *= 1-clamp(intent.throttle*1.6,0,.9)
    target_descent := -1.35-intent.climb*1.2
    lift := max(target_descent-velocity.y,f32(0))*mass*3.2*factor
    horizontal := third_person.Vec3{velocity.x,0,velocity.z}
    drag := horizontal*(-mass*.72*factor)
    return {factor=factor,lift=clamp(lift,0,310),drag=drag}
}

witch_smooth_volume :: proc(position, center, half_size: third_person.Vec3) -> f32 {
    nx := math.abs(position.x - center.x) / half_size.x
    ny := math.abs(position.y - center.y) / half_size.y
    nz := math.abs(position.z - center.z) / half_size.z
    edge := max(nx, max(ny, nz))
    return 1 - clamp((edge - .72) / .28, 0, 1)
}

witch_wind_at :: proc(position: third_person.Vec3, time: f32) -> third_person.Vec3 {
    // Deterministic, low-frequency gusts arrive from upwind before the broom.
    phase := position.x * .025 + position.z * .012 - time * 1.4
    gust := f32(math.sin(f64(phase))) * 1.7 + f32(math.sin(f64(phase * .37 + 2.1))) * .9
    wind := third_person.Vec3{2.2 + gust, .15, .8}
    thermal := witch_smooth_volume(position, {34, 18, 58}, {15, 32, 15})
    thermal_radius := witch_length(third_person.Vec3{position.x - 34, 0, position.z - 58})
    wind.y += thermal * (8.5 - min(thermal_radius * .18, f32(2.5)))
    crosswind := witch_smooth_volume(position, {-18, 11, 48}, {23, 18, 14})
    wind.x += crosswind * 9.5
    ridge_up := f32(math.exp(-f64((position.z - 82) * (position.z - 82)) / 170))
    wind.y += ridge_up * 6.5
    rotor := witch_smooth_volume(position, {0, 13, 111}, {45, 16, 17})
    wind.x += rotor * f32(math.sin(f64(position.z * .23 + time * 2.1))) * 4
    wind.y += rotor * f32(math.sin(f64(position.x * .19 - time * 1.7))) * 3.5
    return wind
}

witch_activity_wind_at :: proc(position: third_person.Vec3,time: f32,activity: Witch_Activity) -> third_person.Vec3 {
    wind := witch_wind_at(position,time)
    if activity == .Flow_Course {
        prevailing := third_person.Vec3{2.2,.15,.8}
        wind = prevailing+(wind-prevailing)*.42
    }
    return wind
}

witch_upcoming_wind :: proc(position: third_person.Vec3,yaw,time: f32,activity: Witch_Activity) -> (strength,side: f32) {
    forward := witch_forward(yaw,0)
    right := witch_right(yaw)
    current := witch_activity_wind_at(position,time,activity)
    ahead := witch_activity_wind_at(position+forward*18,time,activity)
    change := ahead-current
    strength = clamp(witch_length(change)/6,0,1)
    side = change.x*right.x+change.z*right.z
    return
}

witch_reset :: proc() {
    config := witch_lab.config
    activity := witch_lab.activity
    debug := witch_lab.debug
    controller_used := witch_lab.controller_used
    invert_horizontal,invert_vertical := witch_lab.invert_horizontal,witch_lab.invert_vertical
    witch_lab = {
        config=config,activity=activity,debug=debug,controller_used=controller_used,
        invert_horizontal=invert_horizontal,invert_vertical=invert_vertical,
    }
    witch_lab.broom.position = {0, 4.2, -61}
    witch_lab.previous_position = witch_lab.broom.position
    witch_lab.broom.yaw = math.PI
    witch_lab.previous_attitude = {witch_lab.broom.pitch,witch_lab.broom.yaw,witch_lab.broom.roll}
    witch_lab.broom.power = config.power_capacity
    witch_lab.broom.grip = 1
    witch_lab.parcel_security = 1
    witch_lab.camera_yaw = math.PI
    witch_lab.camera_pitch = .40
    witch_lab.camera_distance = 8.6
    witch_lab.last_time = f32(canvas2d.GetTime())
}

witch_activity_start :: proc(activity: Witch_Activity) {
    witch_lab.activity = activity
    witch_reset()
}

witch_resolve_tree_collisions :: proc() {
    b := &witch_lab.broom
    for tree in witch_trees {
        ground := witch_ground_height(tree.x, tree.z)
        if b.position.y < ground + .25 || b.position.y > ground + 10.5*tree.scale do continue
        delta := third_person.Vec3{b.position.x-tree.x, 0, b.position.z-tree.z}
        distance := witch_length(delta)
        // The trunk is firm while the broad crown gives a softer readable hit.
        trunk_radius := .65*tree.scale + .55
        crown_radius := 3.1*tree.scale + .55
        crown := b.position.y > ground + 4.8*tree.scale
        radius := crown ? crown_radius : trunk_radius
        if distance >= radius do continue
        normal := witch_safe_normalize(delta, {1,0,0})
        b.position += normal*(radius-distance)
        impact_speed := max(-(b.velocity.x*normal.x+b.velocity.z*normal.z), f32(0))
        if impact_speed > 0 {
            b.velocity += normal*impact_speed*1.35
            b.velocity *= crown ? f32(.68) : f32(.52)
            b.angular_velocity.z += (normal.x*.9-normal.z*.45)*min(impact_speed*.08, f32(1.5))
            b.grip = clamp(b.grip-impact_speed*(crown?.018:.032), 0, 1)
            witch_lab.collision_time = .55
        }
    }
}

witch_update_activity :: proc(dt: f32) {
    b := &witch_lab.broom
    witch_lab.ring_pass_time = max(witch_lab.ring_pass_time-dt,f32(0))
    if witch_lab.activity_complete {
        witch_lab.completion_time += dt
        return
    }
    switch witch_lab.activity {
    case .Flow_Course:
        if witch_lab.ring_index < WITCH_RING_COUNT &&
           witch_length(b.position-witch_ring_positions[witch_lab.ring_index]) < WITCH_RING_RADIUS+1.6 {
            witch_lab.ring_pass_position = witch_ring_positions[witch_lab.ring_index]
            witch_lab.ring_pass_time = .65
            witch_lab.ring_index += 1
        }
        witch_lab.activity_complete = witch_lab.ring_index == WITCH_RING_COUNT
    case .Wind_Crossing:
        // The parcel remains recoverable; security affects the result, not failure.
        witch_lab.activity_complete = b.position.z > 72 && b.position.y > witch_ground_height(b.position.x,b.position.z)+2
    case .Thermal_Landing:
        in_thermal := witch_smooth_volume(b.position, {34,18,58}, {15,32,15}) > .45
        if in_thermal && b.position.y > 24 do witch_lab.thermal_reached = true
        witch_lab.activity_complete = witch_lab.thermal_reached && witch_lab.landed
    }
}

witch_axis :: proc(value: f32, deadzone: f32 = .16) -> f32 {
    magnitude := math.abs(value)
    if magnitude <= deadzone do return 0
    shaped := clamp((magnitude - deadzone) / (1 - deadzone), 0, 1)
    shaped *= shaped * (3 - 2 * shaped)
    return math.sign(value) * shaped
}

witch_map_left_stick :: proc(horizontal,vertical: f32,invert_horizontal,invert_vertical: bool) -> (steer,climb: f32) {
    steer = invert_horizontal ? -horizontal : horizontal
    climb = invert_vertical ? vertical : -vertical
    return
}

witch_axis_toggle_bounds :: proc(width: f32,vertical: bool) -> canvas2d.Rectangle {
    return {width-238,vertical ? f32(58) : f32(22),216,28}
}

witch_replay_bounds :: proc(width,height: f32) -> canvas2d.Rectangle {
    return {width*.5-105,height-82,210,34}
}

witch_activity_button_bounds :: proc(index: int) -> canvas2d.Rectangle {
    return {22+f32(index)*144,158,136,30}
}

witch_activity_offset :: proc(activity: Witch_Activity,offset: int) -> Witch_Activity {
    count := 3
    index := (int(activity)+offset)%count
    if index<0 do index += count
    return Witch_Activity(index)
}

witch_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    witch_lab = {config = witch_default_config()}
    switch target {
    case "", "flow", "circuit", "acceleration", "braking", "strain", "camera-tree", "low-power", "complete", "ring-pass", "debug": witch_lab.activity = .Flow_Course
    case "wind", "gust": witch_lab.activity = .Wind_Crossing
    case "thermal": witch_lab.activity = .Thermal_Landing
    case "landing": witch_lab.activity = .Thermal_Landing
    case "recovery": witch_lab.activity = .Flow_Course
    case: return false
    }
    witch_reset()
    if target == "recovery" {
        witch_lab.broom.recovery_time = 1.1
        witch_lab.broom.grip = .12
        witch_lab.broom.rider_state = .Recovering
    }
    if target == "landing" {
        ground := witch_ground_height(42,126)
        witch_lab.broom.position = {42,ground+4,126}
        witch_lab.previous_position = witch_lab.broom.position
        witch_lab.broom.velocity = {0,-2.4,3.2}
        witch_lab.broom.yaw = math.PI
        witch_lab.previous_attitude = {0,math.PI,0}
        witch_lab.thermal_reached = true
        witch_lab.camera_yaw = math.PI
    }
    if target == "camera-tree" {
        tree := witch_trees[0]
        ground := witch_ground_height(tree.x,tree.z)
        witch_lab.broom.position = {tree.x,ground+4,tree.z+4}
        witch_lab.previous_position = witch_lab.broom.position
        witch_lab.broom.yaw = math.PI
        witch_lab.previous_attitude = {0,math.PI,0}
        witch_lab.camera_yaw = math.PI
        witch_lab.camera_obstruction_snap = true
    }
    if target == "low-power" {
        witch_lab.broom.power = 8
        witch_lab.broom.velocity = {0,-.8,10}
        witch_lab.broom.rider_state = .Straining
    }
    if target == "gust" {
        witch_lab.broom.position = {-18,11,26}
        witch_lab.previous_position = witch_lab.broom.position
        witch_lab.broom.velocity = {0,0,11}
        witch_lab.broom.yaw = math.PI
        witch_lab.previous_attitude = {0,math.PI,0}
    }
    if target == "complete" {
        witch_lab.ring_index = WITCH_RING_COUNT
        witch_lab.activity_complete = true
        witch_lab.completion_time = .35
    }
    if target == "ring-pass" {
        witch_lab.ring_index = 1
        witch_lab.ring_pass_position = witch_ring_positions[0]
        witch_lab.ring_pass_time = .48
    }
    if target == "debug" do witch_lab.debug = true
    if target == "circuit" do witch_lab.show_course_overview = true
    if target == "acceleration" {
        witch_lab.pose_preview = 1
        witch_lab.intent.throttle = 1
        witch_lab.flight_intent.throttle = 1
        witch_lab.broom.velocity = {0,0,12}
    } else if target == "braking" {
        witch_lab.pose_preview = 2
        witch_lab.intent.brake = 1
        witch_lab.flight_intent.brake = 1
        witch_lab.broom.velocity = {0,0,16}
    } else if target == "strain" {
        witch_lab.pose_preview = 3
        witch_lab.broom.rider_state = .Straining
        witch_lab.broom.grip = .48
        witch_lab.broom.shaft_flex = .85
        witch_lab.broom.wind = {13,2,1}
    }
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.project.sea_level = -8
    atmosphere.set_world_minutes(&editor.atmosphere, 17 * 60 + 10)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    set_pointer_locked(false)
    witch_update_camera(editor)
    return true
}

witch_sample_input :: proc() -> Witch_Input_Frame {
    frame: Witch_Input_Frame
    intent: Witch_Intent
    keyboard_active := false
    if canvas2d.IsKeyDown(.W) {intent.throttle = 1; keyboard_active = true}
    if canvas2d.IsKeyDown(.S) {intent.brake = 1; keyboard_active = true}
    if canvas2d.IsKeyDown(.A) || canvas2d.IsKeyDown(.LEFT) {intent.steer -= 1; keyboard_active = true}
    if canvas2d.IsKeyDown(.D) || canvas2d.IsKeyDown(.RIGHT) {intent.steer += 1; keyboard_active = true}
    if canvas2d.IsKeyDown(.SPACE) || canvas2d.IsKeyDown(.UP) {intent.climb += 1; keyboard_active = true}
    if canvas2d.IsKeyDown(.C) || canvas2d.IsKeyDown(.DOWN) {intent.climb -= 1; keyboard_active = true}
    intent.brace = canvas2d.IsKeyDown(.LEFT_SHIFT) || canvas2d.IsKeyDown(.RIGHT_SHIFT)
    if intent.brace do keyboard_active = true
    mouse := canvas2d.GetMouseDelta()
    if math.abs(mouse.x) + math.abs(mouse.y) > .2 {
        intent.orbit_x = -mouse.x * .004
        intent.orbit_y = -mouse.y * .003
        keyboard_active = true
    }
    if canvas2d.GamepadAvailable() {
        lx := witch_axis(canvas2d.GetGamepadAxis(.Left_X), witch_lab.config.stick_deadzone)
        ly := witch_axis(canvas2d.GetGamepadAxis(.Left_Y), witch_lab.config.stick_deadzone)
        rx := witch_axis(canvas2d.GetGamepadAxis(.Right_X), witch_lab.config.camera_stick_deadzone)
        ry := witch_axis(canvas2d.GetGamepadAxis(.Right_Y), witch_lab.config.camera_stick_deadzone)
        rt := max(witch_axis(canvas2d.GetGamepadAxis(.Right_Trigger), witch_lab.config.trigger_deadzone), f32(0))
        lt := max(witch_axis(canvas2d.GetGamepadAxis(.Left_Trigger), witch_lab.config.trigger_deadzone), f32(0))
        if math.abs(lx)+math.abs(ly)+math.abs(rx)+math.abs(ry)+rt+lt > .02 || canvas2d.IsGamepadButtonDown(.Left_Shoulder) {
            steer,climb := witch_map_left_stick(lx,ly,witch_lab.invert_horizontal,witch_lab.invert_vertical)
            intent.steer = clamp(steer*1.22,-1,1); intent.climb = clamp(climb*1.18,-1,1); intent.throttle = rt; intent.brake = lt
            intent.orbit_x = -rx * .035; intent.orbit_y = ry * .025
            intent.brace = canvas2d.IsGamepadButtonDown(.Left_Shoulder)
            frame.gamepad_active = true
        }
    }
    gamepad_available := canvas2d.GamepadAvailable()
    keyboard_reset := canvas2d.IsKeyPressed(.R)
    keyboard_replay := canvas2d.IsKeyPressed(.F)
    keyboard_debug := canvas2d.IsKeyPressed(.V)
    gamepad_reset := gamepad_available && canvas2d.IsGamepadButtonPressed(.Back)
    gamepad_replay := gamepad_available && canvas2d.IsGamepadButtonPressed(.South)
    gamepad_recenter := gamepad_available && canvas2d.IsGamepadButtonPressed(.North)
    gamepad_debug := gamepad_available && canvas2d.IsGamepadButtonPressed(.Dpad_Up)
    frame.reset = keyboard_reset || gamepad_reset
    frame.replay = keyboard_replay || gamepad_replay
    frame.recenter = gamepad_recenter
    frame.activity_1 = canvas2d.IsKeyPressed(.ONE)
    frame.activity_2 = canvas2d.IsKeyPressed(.TWO)
    frame.activity_3 = canvas2d.IsKeyPressed(.THREE)
    frame.activity_previous = gamepad_available && canvas2d.IsGamepadButtonPressed(.Dpad_Left)
    frame.activity_next = gamepad_available && canvas2d.IsGamepadButtonPressed(.Dpad_Right)
    frame.debug_toggle = keyboard_debug || gamepad_debug
    frame.recovery_demo = canvas2d.IsKeyPressed(.B)
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        pointer := canvas2d.GetMousePosition()
        width := f32(canvas2d.GetScreenWidth())
        height := f32(canvas2d.GetScreenHeight())
        frame.toggle_horizontal = canvas2d.CheckCollisionPointRec(pointer,witch_axis_toggle_bounds(width,false))
        frame.toggle_vertical = canvas2d.CheckCollisionPointRec(pointer,witch_axis_toggle_bounds(width,true))
        frame.activity_1 = frame.activity_1 || canvas2d.CheckCollisionPointRec(pointer,witch_activity_button_bounds(0))
        frame.activity_2 = frame.activity_2 || canvas2d.CheckCollisionPointRec(pointer,witch_activity_button_bounds(1))
        frame.activity_3 = frame.activity_3 || canvas2d.CheckCollisionPointRec(pointer,witch_activity_button_bounds(2))
        if witch_lab.activity_complete && canvas2d.CheckCollisionPointRec(pointer,witch_replay_bounds(width,height)) do frame.replay = true
        if frame.toggle_horizontal || frame.toggle_vertical || frame.activity_1 || frame.activity_2 || frame.activity_3 || frame.replay do canvas2d.ConsumeMouseButtonPressed(.LEFT)
    }
    if gamepad_reset || gamepad_replay || gamepad_recenter || gamepad_debug {
        frame.gamepad_active = true
    }
    if frame.activity_previous || frame.activity_next do frame.gamepad_active = true
    if keyboard_active || frame.activity_1 || frame.activity_2 || frame.activity_3 ||
       keyboard_reset || keyboard_replay || keyboard_debug || frame.toggle_horizontal || frame.toggle_vertical {
        frame.gamepad_active = false
    }
    frame.intent = intent
    return frame
}

witch_lab_process_input :: proc(editor: ^Editor) {
    frame := witch_sample_input()
    if frame.toggle_horizontal do witch_lab.invert_horizontal = !witch_lab.invert_horizontal
    if frame.toggle_vertical do witch_lab.invert_vertical = !witch_lab.invert_vertical
    if frame.gamepad_active {
        witch_lab.controller_used = true
    } else if frame.intent != {} || frame.activity_1 || frame.activity_2 || frame.activity_3 ||
              frame.reset || frame.recenter || frame.debug_toggle {
        witch_lab.controller_used = false
    }
    if frame.reset do witch_reset()
    if witch_lab.activity_complete && frame.replay do witch_activity_start(witch_lab.activity)
    if frame.activity_1 {
        witch_activity_start(.Flow_Course)
    } else if frame.activity_2 {
        witch_activity_start(.Wind_Crossing)
    } else if frame.activity_3 {
        witch_activity_start(.Thermal_Landing)
    } else if frame.activity_previous {
        witch_activity_start(witch_activity_offset(witch_lab.activity,-1))
    } else if frame.activity_next {
        witch_activity_start(witch_activity_offset(witch_lab.activity,1))
    }
    if frame.debug_toggle do witch_lab.debug = !witch_lab.debug
    if witch_lab.debug && frame.recovery_demo {
        witch_lab.broom.recovery_time = 2.2
        witch_lab.broom.grip = .08
    }
    if frame.recenter {
        witch_lab.camera_yaw = witch_lab.broom.yaw
        witch_lab.camera_pitch = .28
    }
    witch_lab.intent = frame.intent
    witch_lab.camera_yaw += frame.intent.orbit_x
    if math.abs(frame.intent.orbit_x)>.0001 || math.abs(frame.intent.orbit_y)>.0001 do witch_lab.camera_orbit_time = .9
    witch_lab.camera_pitch = clamp(witch_lab.camera_pitch + frame.intent.orbit_y, -.05, .68)
    witch_update_camera(editor)
}

witch_step :: proc(dt, time: f32) {
    b := &witch_lab.broom
    c := &witch_lab.config
    // Presentation reads raw intent immediately; force production ramps so
    // full-stick corrections remain controllable on a gamepad.
    witch_lab.flight_intent.steer = witch_approach(witch_lab.flight_intent.steer,witch_lab.intent.steer,dt*4.2)
    witch_lab.flight_intent.climb = witch_approach(witch_lab.flight_intent.climb,witch_lab.intent.climb,dt*3.8)
    witch_lab.flight_intent.throttle = witch_approach(witch_lab.flight_intent.throttle,witch_lab.intent.throttle,dt*2.6)
    witch_lab.flight_intent.brake = witch_approach(witch_lab.flight_intent.brake,witch_lab.intent.brake,dt*4.5)
    witch_lab.flight_intent.brace = witch_lab.intent.brace
    intent := witch_lab.flight_intent
    witch_lab.camera_orbit_time = max(witch_lab.camera_orbit_time-dt,f32(0))
    if witch_lab.camera_orbit_time <= 0 {
        witch_lab.camera_yaw += clamp(witch_angle_delta(b.yaw,witch_lab.camera_yaw),-dt*2.8,dt*2.8)
    }
    mass := c.broom_mass + c.rider_mass
    ground := witch_ground_height(b.position.x, b.position.z)
    altitude := b.position.y - ground
    b.wind = witch_activity_wind_at(b.position,time,witch_lab.activity)
    witch_lab.gust_warning,witch_lab.gust_side = witch_upcoming_wind(b.position,b.yaw,time,witch_lab.activity)
    relative_air := b.velocity - b.wind
    speed := witch_length(b.velocity)
    airspeed := witch_length(relative_air)

    desired_roll := -intent.steer * (.32 + min(speed / 24, f32(1)) * .42)
    desired_pitch := intent.climb * .30 - intent.brake * .12
    landing := witch_landing_assistance(b.position,b.velocity,intent,mass)
    witch_lab.landing_assist = landing.factor
    desired_roll *= 1-landing.factor*.72
    desired_pitch *= 1-landing.factor*.58
    if intent.brace {desired_roll *= .72; desired_pitch *= .78}
    b.angular_velocity.x += ((desired_pitch - b.pitch) * c.attitude_gain - b.angular_velocity.x * c.angular_damping) * dt
    b.angular_velocity.z += ((desired_roll - b.roll) * c.attitude_gain - b.angular_velocity.z * c.angular_damping) * dt
    yaw_authority := .35 + min(speed / 13, f32(1))
    // A broom turns around its compact rider/broom inertia, not total mass as
    // if it were an aircraft fuselage. Bank input therefore produces a clear
    // coordinated heading change even at meadow speed.
    yaw_inertia := f32(18)
    b.angular_velocity.y += (intent.steer * c.yaw_torque / yaw_inertia * yaw_authority - b.angular_velocity.y * 2.35) * dt
    b.pitch = clamp(b.pitch + b.angular_velocity.x * dt, -.65, .58)
    b.roll = clamp(b.roll + b.angular_velocity.z * dt, -.92, .92)
    b.yaw += b.angular_velocity.y * dt

    forward := witch_forward(b.yaw, b.pitch)
    right := witch_right(b.yaw)
    up := third_person.Vec3{-right.x * f32(math.sin(f64(b.roll))), f32(math.cos(f64(b.roll))), -right.z * f32(math.sin(f64(b.roll)))}
    power_fraction := clamp(b.power/c.power_capacity,0,1)
    axis_agility := intent.brace ? f32(.72) : f32(1)
    vertical_target_speed := intent.climb*c.vertical_control_speed*(intent.brace ? f32(.84) : f32(1))
    vertical_control_acceleration := clamp(
        (vertical_target_speed-b.velocity.y)*c.axis_control_gain,
        -c.axis_control_acceleration,
        c.axis_control_acceleration,
    )
    lift_need := mass*9.81+vertical_control_acceleration*mass
    if altitude < 5 && b.velocity.y < 0 do lift_need += (5-altitude) * c.ground_assist
    lift_need += witch_terrain_lookahead_lift(b.position,b.velocity,intent.climb,c.ground_assist)
    lift_need += landing.lift
    lift := min(lift_need,c.max_support_force*(.52+.48*power_fraction))
    propulsion_input := witch_propulsion_input(intent,c.cruise_throttle)
    thrust := propulsion_input*c.forward_thrust*(.48+.52*power_fraction)
    brake_force := min(intent.brake * c.braking_force, speed * mass / max(dt, f32(.001)))
    velocity_forward := witch_safe_normalize(b.velocity, forward)
    drag := relative_air * (-c.linear_drag * min(airspeed, f32(42)))
    lateral_speed := b.velocity.x*right.x + b.velocity.z*right.z
    lateral_target_speed := intent.steer*c.lateral_control_speed*axis_agility
    lateral_control_acceleration := clamp(
        (lateral_target_speed-lateral_speed)*c.axis_control_gain,
        -c.axis_control_acceleration,
        c.axis_control_acceleration,
    )
    lateral_control := right*(lateral_control_acceleration*mass)
    drag -= right * lateral_speed * c.lateral_drag * mass
    gravity := third_person.Vec3{0, -mass * 9.81, 0}
    support := up * lift
    propulsion := forward * thrust
    braking := velocity_forward * -brake_force
    b.segment_forces[0] = support * .28 + propulsion * .46
    avoidance_force := witch_obstacle_avoidance_acceleration(b.position,b.velocity,intent.steer)*mass
    b.segment_forces[1] = support*.44+drag+gravity+landing.drag+avoidance_force+lateral_control
    b.segment_forces[2] = support * .28 + propulsion * .54 + braking
    b.net_force = b.segment_forces[0] + b.segment_forces[1] + b.segment_forces[2]
    control_torque := third_person.Vec3{
        (desired_pitch-b.pitch)*c.pitch_torque,
        intent.steer*c.yaw_torque,
        (desired_roll-b.roll)*c.roll_torque,
    }
    // Forces are applied at the broom's front, middle, and rear. Keep this
    // resultant explicit so tuning and debug views expose the same model.
    segment_offsets := [3]third_person.Vec3{forward*2.2, {}, forward*-2.2}
    b.net_torque = control_torque
    for force,index in b.segment_forces do b.net_torque += witch_cross(segment_offsets[index],force)
    acceleration := b.net_force / mass
    accel_length := witch_length(acceleration)
    if accel_length > c.max_acceleration do acceleration *= c.max_acceleration / accel_length
    b.desired_acceleration = up*(lift/mass-9.81)+forward*(thrust/mass)+right*lateral_control_acceleration
    b.actual_acceleration = acceleration
    b.velocity += acceleration * dt
    max_speed := witch_lab.activity == .Flow_Course ? f32(27) : f32(34)
    if witch_length(b.velocity) > max_speed do b.velocity *= max_speed / witch_length(b.velocity)
    b.position += b.velocity * dt

    witch_resolve_tree_collisions()

    if b.position.y < ground + .72 {
        b.position.y = ground + .72
        if b.velocity.y < -5 {b.grip -= min(-b.velocity.y * .018, f32(.18))}
        b.velocity.y = math.abs(b.velocity.y) * .18
        contact_damping := clamp(1-(2.6+landing.factor*4)*dt,0,1)
        b.velocity.x *= contact_damping; b.velocity.z *= contact_damping
        b.roll *= .78; b.pitch *= .78
    }

    load := witch_length(acceleration) / c.comfortable_acceleration
    wind_load := airspeed * airspeed * .00075
    angular_load := witch_length(b.angular_velocity) * .32
    raw_danger := load + wind_load + angular_load
    auto_brace := !intent.brace && (raw_danger>1.15 || witch_lab.gust_warning>.7)
    tolerance_multiplier := intent.brace ? c.brace_multiplier : (auto_brace ? f32(1.2) : f32(1))
    tolerance := c.grip_strength * tolerance_multiplier
    danger := raw_danger / tolerance
    if danger > 1.15 {b.grip -= (danger - 1.15) * .13 * dt} else {b.grip += (intent.brace ? f32(.17) : f32(.08)) * dt}
    b.grip = clamp(b.grip, 0, 1)
    if b.recovery_time > 0 {
        b.recovery_time -= dt
        b.rider_state = .Recovering
        b.grip += .34 * dt
        b.velocity.y += 4.2 * dt
    } else if b.grip < .08 {
        b.recovery_time = 2.2
        b.rider_state = .Critical
    } else if b.grip < .22 {b.rider_state = .Critical
    } else if b.grip < .42 {b.rider_state = .Slipping
    } else if danger > 1.2 {b.rider_state = .Straining
    } else if intent.brace || auto_brace || danger > .9 {b.rider_state = .Bracing
    } else {b.rider_state = .Comfortable}
    b.grip = clamp(b.grip, 0, 1)

    demand := 2.1 + intent.throttle*7.5 + max(intent.climb, f32(0))*5 + witch_length(b.net_torque)*.035
    if intent.throttle < .15 && intent.climb <= 0 do demand -= c.power_recovery
    b.power = clamp(b.power - demand * dt, 0, c.power_capacity)
    target_flex := clamp((thrust + lift*.18) / 900, 0, 1) * (intent.brace ? f32(.78) : f32(1))
    b.shaft_flex += (target_flex - b.shaft_flex) * min(c.shaft_stiffness * dt, f32(1))

    if witch_lab.activity == .Wind_Crossing {
        parcel_danger := max(danger - (intent.brace ? f32(.72) : f32(.45)), f32(0))
        witch_lab.parcel_security = clamp(witch_lab.parcel_security - parcel_danger*.08*dt + .025*dt, .15, 1)
    }
    landing_ground := witch_ground_height(42, 132)
    on_landing := math.abs(b.position.x-42)<18 && math.abs(b.position.z-132)<13 && b.position.y < landing_ground+1.5
    witch_lab.landed = on_landing && witch_length(b.velocity) < 4
    witch_lab.collision_time = max(witch_lab.collision_time-dt, f32(0))
    witch_update_activity(dt)
}

witch_update_camera :: proc(editor: ^Editor) {
    if editor == nil do return
    b := &witch_lab.broom
    render_position := witch_render_position()
    render_attitude := witch_render_attitude()
    follow := render_position + third_person.Vec3{0, 1.35, 0}
    speed_pullback := clamp(witch_length(b.velocity)/34,0,1)*2.8
    camera_distance := witch_lab.camera_distance+speed_pullback
    horizontal := f32(math.cos(f64(witch_lab.camera_pitch))) * camera_distance
    eye := follow + third_person.Vec3{
        -f32(math.sin(f64(witch_lab.camera_yaw))) * horizontal,
        f32(math.sin(f64(witch_lab.camera_pitch))) * camera_distance + 1.55,
        f32(math.cos(f64(witch_lab.camera_yaw))) * horizontal,
    }
    desired_eye := eye
    obstruction_target := witch_camera_avoid_trees(follow,desired_eye)-desired_eye
    if witch_lab.camera_obstruction_snap {
        witch_lab.camera_obstruction_offset = obstruction_target
    } else {
        response := witch_length(obstruction_target)>witch_length(witch_lab.camera_obstruction_offset) ? f32(8.5) : f32(5.5)
        blend := 1-f32(math.exp(f64(-response*clamp(witch_lab.camera_frame_dt,0,.05))))
        witch_lab.camera_obstruction_offset += (obstruction_target-witch_lab.camera_obstruction_offset)*blend
    }
    eye = desired_eye+witch_lab.camera_obstruction_offset
    obstruction_offset := witch_length(witch_lab.camera_obstruction_offset)
    camera_ground := witch_ground_height(eye.x, eye.z) + 1
    eye.y = max(eye.y, camera_ground)
    look_ahead := 3*(1-clamp(obstruction_offset/8,0,1))
    editor.camera_pose = third_person.camera_look_at(eye, follow + witch_forward(render_attitude.y, 0)*look_ahead)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

witch_camera_avoid_trees :: proc(follow,desired_eye: third_person.Vec3) -> third_person.Vec3 {
    result := desired_eye
    // Preserve framing first: orbit sideways around a blocking canopy rather
    // than immediately zooming into the rider's back.
    for tree in witch_trees {
        ray := result-follow
        ray_length := witch_length(ray)
        if ray_length<.001 do continue
        center := third_person.Vec3{tree.x,witch_ground_height(tree.x,tree.z)+5.2*tree.scale,tree.z}
        to_center := center-follow
        projection := clamp((to_center.x*ray.x+to_center.y*ray.y+to_center.z*ray.z)/(ray_length*ray_length),0,1)
        closest := follow+ray*projection
        radius := 3.25*tree.scale
        offset := center-closest
        if offset.x*offset.x+offset.y*offset.y+offset.z*offset.z>=radius*radius do continue
        side := witch_safe_normalize(third_person.Vec3{ray.z,0,-ray.x},{1,0,0})
        center_side := offset.x*side.x+offset.z*side.z
        away_sign := center_side>=0 ? f32(-1) : f32(1)
        result += side*(away_sign*(radius*4+.35))
    }

    ray := result-follow
    ray_length := witch_length(ray)
    if ray_length<.001 do return result
    ray_length_squared := ray_length*ray_length
    allowed_fraction := f32(1)
    for tree in witch_trees {
        center := third_person.Vec3{tree.x,witch_ground_height(tree.x,tree.z)+5.2*tree.scale,tree.z}
        to_center := center-follow
        projection := clamp((to_center.x*ray.x+to_center.y*ray.y+to_center.z*ray.z)/ray_length_squared,0,1)
        closest := follow+ray*projection
        radius := 3.25*tree.scale
        offset := center-closest
        distance_squared := offset.x*offset.x+offset.y*offset.y+offset.z*offset.z
        if distance_squared>=radius*radius do continue
        half_chord := f32(math.sqrt(f64(max(radius*radius-distance_squared,f32(0)))))
        entry_fraction := projection-half_chord/ray_length
        allowed_fraction = min(allowed_fraction,max(entry_fraction-.04,f32(.24)))
    }
    return follow+ray*allowed_fraction
}

witch_simulate_frame :: proc(editor: ^Editor) {
    now := f32(canvas2d.GetTime())
    if pause_menu_is_open(editor) {
        // Do not accumulate wall-clock debt while the shared pause menu owns input.
        witch_lab.last_time = now
        witch_update_camera(editor)
        return
    }
    frame_dt := clamp(now - witch_lab.last_time, f32(0), f32(.10))
    witch_lab.last_time = now
    witch_lab.camera_frame_dt = frame_dt
    witch_lab.accumulator += frame_dt
    steps := 0
    for witch_lab.accumulator >= WITCH_FIXED_DT && steps < WITCH_MAX_STEPS {
        witch_lab.previous_position = witch_lab.broom.position
        witch_lab.previous_attitude = {witch_lab.broom.pitch,witch_lab.broom.yaw,witch_lab.broom.roll}
        witch_step(WITCH_FIXED_DT, now - witch_lab.accumulator)
        witch_lab.accumulator -= WITCH_FIXED_DT
        steps += 1
    }
    if steps == WITCH_MAX_STEPS do witch_lab.accumulator = min(witch_lab.accumulator, WITCH_FIXED_DT)
    witch_update_camera(editor)
}

witch_ring_positions := [WITCH_RING_COUNT]third_person.Vec3{
    {0,8,-34}, {-18,9,-12}, {-42,11,10}, {-54,14,38},
    {-44,17,66}, {-20,22,86}, {10,25,98}, {38,20,112},
    {55,16,136}, {30,20,148}, {0,24,142}, {-28,21,128},
    {-52,17,107}, {-60,15,80}, {-48,12,52}, {-32,10,24},
    {-18,8,-4}, {0,7,-34},
}

witch_render_position :: proc() -> third_person.Vec3 {
    alpha := clamp(witch_lab.accumulator/WITCH_FIXED_DT,0,1)
    return witch_lab.previous_position*(1-alpha)+witch_lab.broom.position*alpha
}

witch_render_attitude :: proc() -> third_person.Vec3 {
    alpha := clamp(witch_lab.accumulator/WITCH_FIXED_DT,0,1)
    current := third_person.Vec3{witch_lab.broom.pitch,witch_lab.broom.yaw,witch_lab.broom.roll}
    return witch_lab.previous_attitude*(1-alpha)+current*alpha
}

witch_ring_direction :: proc(index: int) -> third_person.Vec3 {
    previous := max(index-1,0)
    next := min(index+1,WITCH_RING_COUNT-1)
    if index == 0 do previous = 0
    if index == WITCH_RING_COUNT-1 do next = WITCH_RING_COUNT-1
    delta := witch_ring_positions[next]-witch_ring_positions[previous]
    delta.y = 0
    return witch_safe_normalize(delta,{0,0,1})
}

witch_draw_ring :: proc(center,direction: third_person.Vec3, radius: f32, color: canvas2d.Color) {
    right := witch_safe_normalize(third_person.Vec3{direction.z,0,-direction.x},{1,0,0})
    for segment in 0..<24 {
        a := f32(segment)/24*math.PI*2
        next_angle := f32(segment+1)/24*math.PI*2
        p0 := center+right*(f32(math.cos(f64(a)))*radius)+third_person.Vec3{0,f32(math.sin(f64(a)))*radius,0}
        p1 := center+right*(f32(math.cos(f64(next_angle)))*radius)+third_person.Vec3{0,f32(math.sin(f64(next_angle)))*radius,0}
        world_tube_between(p0,p1,direction,.18,.18,color)
    }
}

witch_draw_ring_pass :: proc() {
    if witch_lab.ring_pass_time<=0 do return
    passed_index := clamp(witch_lab.ring_index-1,0,WITCH_RING_COUNT-1)
    direction := witch_ring_direction(passed_index)
    right := witch_safe_normalize(third_person.Vec3{direction.z,0,-direction.x},{1,0,0})
    age := .65-witch_lab.ring_pass_time
    fade := clamp(witch_lab.ring_pass_time/.65,0,1)
    radius := WITCH_RING_RADIUS+.5+age*3.2
    for spark in 0..<12 {
        angle := f32(spark)/12*math.PI*2
        outward := right*f32(math.cos(f64(angle)))+third_person.Vec3{0,f32(math.sin(f64(angle))),0}
        start := witch_lab.ring_pass_position+outward*radius
        color := spark&1==0 ? canvas2d.Color{120,236,192,u8(220*fade)} : canvas2d.Color{255,224,112,u8(210*fade)}
        world_tube_between(start,start+outward*(.5+fade*.75),direction,.07,.018,color)
    }
}

witch_draw_tree :: proc(x, z, scale: f32) {
    ground := witch_ground_height(x,z)
    world_tube_between({x,ground,z},{x,ground+8*scale,z},{0,0,1},.65*scale,.65*scale,{104,70,43,255})
    for layer in 0..<3 {
        y := ground + (5.5+f32(layer)*2.0)*scale
        radius := (3.8-f32(layer)*.7)*scale
        for branch in 0..<6 {
            angle := f32(branch)/6*math.PI*2 + f32(layer)*.35
            end := third_person.Vec3{x+f32(math.cos(f64(angle)))*radius,y+.9*scale,z+f32(math.sin(f64(angle)))*radius}
            world_tube_between({x,y-.5*scale,z},end,{0,1,0},.85*scale,.18*scale,{47,108+u8(layer)*8,66,255})
        }
    }
}

witch_pose_parameters :: proc(b: Witch_Broom_State,intent: Witch_Intent,landing_factor: f32) -> Witch_Pose_Params {
    right := witch_right(b.yaw)
    relative_wind := b.wind-b.velocity
    crosswind := relative_wind.x*right.x+relative_wind.z*right.z
    wind_lean := clamp(crosswind*.025,-.30,.30)
    brace := b.rider_state == .Bracing || b.rider_state == .Straining || b.rider_state == .Critical
    strain: f32
    #partial switch b.rider_state {
    case .Straining: strain = .48
    case .Slipping: strain = .68
    case .Critical: strain = 1
    case .Recovering: strain = .72
    case: strain = 0
    }
    low_power := 1-clamp(b.power/22,0,1)
    strain = max(strain,low_power*.78)
    acceleration_crouch := intent.throttle*.15
    return {
        lean = -intent.steer*.34+b.roll*.24+wind_lean,
        crouch = brace ? f32(.34) : max(max(acceleration_crouch,landing_factor*.12),low_power*.16),
        torso_fore_aft = intent.throttle*.30-intent.brake*.28,
        head_fore_aft = intent.throttle*.24-intent.brake*.36-low_power*.16,
        strain = strain,
    }
}

witch_transform :: proc(local: third_person.Vec3) -> third_person.Vec3 {
    attitude := witch_render_attitude()
    forward := witch_forward(attitude.y,attitude.x)
    right := witch_right(attitude.y)
    up := third_person.Vec3{0,1,0}
    return witch_render_position() + right*local.x + up*local.y + forward*local.z
}

witch_draw_witch :: proc() {
    b := &witch_lab.broom
    pose_broom := b^
    pose_intent := witch_lab.intent
    if witch_lab.pose_preview == 1 {
        pose_intent.throttle = 1
    } else if witch_lab.pose_preview == 2 {
        pose_intent.brake = 1
    } else if witch_lab.pose_preview == 3 {
        pose_broom.rider_state = .Straining
        pose_broom.wind = {13,2,1}
    }
    attitude := witch_render_attitude()
    forward := witch_forward(attitude.y,attitude.x)
    shaft_back := witch_transform({0,-.05,-2.7})
    pose := witch_pose_parameters(pose_broom,pose_intent,witch_lab.landing_assist)
    chatter := pose.strain*f32(math.sin(canvas2d.GetTime()*34))*.055
    shaft_front := witch_transform({chatter,.04+b.shaft_flex*.16,2.6})
    world_tube_between(shaft_back,shaft_front,{0,1,0},.10,.10,{112,70,39,255})
    for bristle in -3..=3 {
        offset := f32(bristle)*.12
        root := witch_transform({offset,-.04,-2.65})
        flare := pose_intent.brake*.32
        bristle_chatter := pose.strain*f32(math.sin(canvas2d.GetTime()*41+f64(bristle)*.7))*.10
        tip := witch_transform({offset*(1+flare)+bristle_chatter,-.10-math.abs(offset)*.15,-3.7-b.shaft_flex*.25})
        world_tube_between(root,tip,{0,1,0},.065,.035,{145,103,48,255})
    }
    brace := pose_broom.rider_state == .Bracing || pose_broom.rider_state == .Straining || pose_broom.rider_state == .Critical
    recovery_progress := b.recovery_time > 0 ? clamp(1-b.recovery_time/2.2,0,1) : f32(0)
    recovery_arc := f32(math.sin(f64(recovery_progress*math.PI)))
    recovery_lift := recovery_arc*1.65
    recovery_side := recovery_arc*.52
    lean := pose.lean
    landing_pose := witch_lab.landing_assist
    crouch := pose.crouch
    slip := b.rider_state == .Slipping ? f32(.38) : (b.rider_state == .Critical ? f32(.65) : f32(0))
    hips := witch_transform({lean+slip+recovery_side,.62-crouch+recovery_lift,0})
    torso := witch_transform({lean+slip*1.2+recovery_side,1.28-crouch+recovery_lift,pose.torso_fore_aft})
    gust_look := clamp(witch_lab.gust_side*.075,-.22,.22)*witch_lab.gust_warning
    head := witch_transform({lean+slip*1.3+recovery_side+gust_look,1.92-crouch+recovery_lift,pose.head_fore_aft})
    world_tube_between(hips,torso,forward,.32,.26,{88,48,126,255})
    world_tube_between(torso,head,forward,.24,.22,{231,178,146,255})
    hat_tip := witch_transform({lean+slip*1.3+recovery_side+gust_look,2.62-crouch+recovery_lift,-.20-b.wind.x*.012})
    world_tube_between(head+third_person.Vec3{0,.18,0},hat_tip,forward,.34,.035,{58,33,82,255})
    hand_front := witch_transform({-.08+recovery_side,.45-crouch*.45+recovery_lift,1.35})
    sides := [2]f32{-1, 1}
    for side in sides {
        shoulder := torso + witch_right(attitude.y)*side*.27
        hand := hand_front + witch_right(attitude.y)*side*(brace?.09:.18)
        world_tube_between(shoulder,hand,forward,.075,.06,{231,178,146,255})
        knee := witch_transform({side*.32+recovery_side,.45-crouch*.7+recovery_lift-landing_pose*.10,-.18})
        foot := witch_transform({side*.24+recovery_side,.14+recovery_lift-landing_pose*.30,brace?.65:.22})
        world_tube_between(hips,knee,forward,.11,.09,{65,43,91,255})
        world_tube_between(knee,foot,forward,.09,.07,{48,34,62,255})
    }
    scarf_root := torso + third_person.Vec3{0,.22,0}
    scarf_tip := scarf_root-forward*(1.1+witch_length(b.velocity-b.wind)*.035)+third_person.Vec3{-b.wind.x*.025,.05,0}
    world_tube_between(scarf_root,scarf_tip,{0,1,0},.09,.035,{220,78,66,255})
    glow := b.power < 22 || pose.strain>.8 ? canvas2d.Color{245,110,96,255} : canvas2d.Color{108,227,207,255}
    glow_flicker := pose.strain*f32(math.sin(canvas2d.GetTime()*23))*.035
    world_tube_between(witch_transform({0,-.02,-2.55}),witch_transform({0,-.02,-2.9}),{0,1,0},.18+glow_flicker,.08,glow)
    if witch_lab.activity == .Wind_Crossing {
        looseness := 1-witch_lab.parcel_security
        sway := f32(math.sin(canvas2d.GetTime()*4.2))*looseness*.42
        parcel := witch_transform({sway,.48-looseness*.22,-.62})
        world_box(parcel,{.66,.5,.72},witch_lab.parcel_security>.45?canvas2d.Color{205,151,73,255}:canvas2d.Color{226,105,75,255})
        tie := witch_transform({0,.57,-.40})
        world_tube_between(tie,parcel,{0,1,0},.035,.035,{238,220,165,255})
    }
}

witch_draw_flight_feedback :: proc() {
    attitude := witch_render_attitude()
    forward := witch_forward(attitude.y,attitude.x)
    right := witch_right(attitude.y)
    center := witch_render_position()+forward*16
    color := canvas2d.Color{124,231,218,150}
    // A sparse world-space flight cue makes the commanded heading legible
    // without pinning a HUD crosshair to the screen.
    world_tube_between(center-right*1.05,center-right*.46,forward,.055,.055,color)
    world_tube_between(center+right*.46,center+right*1.05,forward,.055,.055,color)
    world_tube_between(center+third_person.Vec3{0,.46,0},center+third_person.Vec3{0,1.05,0},forward,.055,.055,color)
    world_tube_between(center-third_person.Vec3{0,.46,0},center-third_person.Vec3{0,1.05,0},forward,.055,.055,color)

    boost := witch_lab.intent.throttle
    if boost>.04 {
        trail_length := 1.2+boost*2.3
        for side in -1..=1 {
            start := witch_transform({f32(side)*.16,-.03,-3.45})
            finish := start-forward*(trail_length-f32(math.abs(side))*.35)
            world_tube_between(start,finish,{0,1,0},.075,.015,{105,235,224,u8(90+boost*130)})
        }
    }
}

witch_draw_approaching_wind :: proc() {
    strength := witch_lab.gust_warning
    if strength<.08 do return
    attitude := witch_render_attitude()
    origin := witch_render_position()
    forward := witch_forward(attitude.y,0)
    right := witch_right(attitude.y)
    now := f32(canvas2d.GetTime())
    alpha := u8(45+strength*125)
    for row in 0..<4 {
        for column in -2..=2 {
            phase := now*5+f32(row*5+column)*.73
            p := origin+forward*(8+f32(row)*5.5)+right*(f32(column)*2.5)+third_person.Vec3{0,1.2+f32(math.sin(f64(phase)))*.7,0}
            wind := witch_activity_wind_at(p,now,witch_lab.activity)
            direction := witch_safe_normalize(wind,{1,0,0})
            length := .45+strength*1.15
            world_tube_between(p-direction*length,p+direction*length*.25,{0,1,0},.045,.018,{207,238,225,alpha})
        }
    }
}

witch_draw_completion_burst :: proc() {
    if !witch_lab.activity_complete || witch_lab.completion_time>2.4 do return
    center := witch_render_position()+third_person.Vec3{0,2.2,0}
    expansion := .8+witch_lab.completion_time*3.2
    fade := 1-clamp(witch_lab.completion_time/2.4,0,1)
    for spark in 0..<14 {
        angle := f32(spark)/14*math.PI*2
        lift := f32((spark*7)%5)*.34-.55
        direction := witch_safe_normalize(third_person.Vec3{f32(math.cos(f64(angle))),lift,f32(math.sin(f64(angle)))},{1,0,0})
        start := center+direction*expansion
        color := spark&1==0 ? canvas2d.Color{255,222,103,u8(220*fade)} : canvas2d.Color{120,231,204,u8(220*fade)}
        world_tube_between(start,start+direction*(.55+fade*.65),{0,1,0},.075,.018,color)
    }
}

witch_draw_physics_debug :: proc() {
    p := witch_render_position()
    world_box(p,{.24,.24,.24},{255,103,91,255})
    rider_center := witch_transform({0,.95,0})
    world_tube_between(p,rider_center,{1,0,0},.055,.055,{239,135,224,255})
    for segment in 0..<20 {
        a := f32(segment)/20*math.PI*2
        next := f32(segment+1)/20*math.PI*2
        p0 := p+third_person.Vec3{f32(math.cos(f64(a)))*.78,0,f32(math.sin(f64(a)))*.78}
        p1 := p+third_person.Vec3{f32(math.cos(f64(next)))*.78,0,f32(math.sin(f64(next)))*.78}
        world_tube_between(p0,p1,{0,1,0},.025,.025,{255,156,91,210})
    }
    torque_length := witch_length(witch_lab.broom.net_torque)
    if torque_length>.001 {
        torque_direction := witch_lab.broom.net_torque/torque_length
        world_tube_between(p,p+torque_direction*min(torque_length*.018,f32(3)),{0,1,0},.065,.025,{209,120,255,255})
    }
}

witch_draw_beacon :: proc(center: third_person.Vec3, color: canvas2d.Color) {
    for segment in 0..<16 {
        a := f32(segment)/16*math.PI*2
        b := f32(segment+1)/16*math.PI*2
        p0 := center+third_person.Vec3{f32(math.cos(f64(a)))*3,.1,f32(math.sin(f64(a)))*3}
        p1 := center+third_person.Vec3{f32(math.cos(f64(b)))*3,.1,f32(math.sin(f64(b)))*3}
        world_tube_between(p0,p1,{0,1,0},.10,.10,color)
    }
    world_tube_between(center+third_person.Vec3{0,.1,0},center+third_person.Vec3{0,8,0},{1,0,0},.09,.09,color)
}

witch_draw_streamer :: proc(x,z,time: f32) {
    ground := witch_ground_height(x,z)
    base := third_person.Vec3{x,ground,z}
    top := base+third_person.Vec3{0,3.4,0}
    world_tube_between(base,top,{0,0,1},.075,.075,{111,82,55,255})
    wind := witch_wind_at(top,time)
    direction := witch_safe_normalize(third_person.Vec3{wind.x,wind.y*.18,wind.z},{1,0,0})
    previous := top
    for segment in 1..=4 {
        phase := time*2.4+f32(segment)*.9+x*.07
        flutter := third_person.Vec3{0,f32(math.sin(f64(phase)))*.14,0}
        next := top+direction*(f32(segment)*.9)+flutter
        color := segment&1==0 ? canvas2d.Color{244,203,101,255} : canvas2d.Color{220,91,69,255}
        world_tube_between(previous,next,{0,1,0},.12,.045,color)
        previous = next
    }
}

world_witch_lab :: proc(editor: ^Editor) {
    if editor == nil do return
    witch_simulate_frame(editor)
    // Broad readable terrain terraces: meadow, valley/stream, ridge and lee.
    for zi in 0..<WITCH_TERRAIN_ROWS {
        for xi in 0..<WITCH_TERRAIN_COLUMNS {
            x := WITCH_TERRAIN_MIN_X+f32(xi)*WITCH_TERRAIN_TILE_X
            z := WITCH_TERRAIN_MIN_Z+f32(zi)*WITCH_TERRAIN_TILE_Z
            y := witch_ground_height(x,z)
            color := z>72 ? canvas2d.Color{93,123,68,255} : canvas2d.Color{91,145,78,255}
            world_box({x,y-4,z},{WITCH_TERRAIN_TILE_X+.15,8,WITCH_TERRAIN_TILE_Z+.15},color)
        }
    }
    world_box({0,witch_ground_height(0,30)+.12,30},{430,.18,7},{47,123,151,230})
    for tree in witch_trees do witch_draw_tree(tree.x,tree.z,tree.scale)
    if witch_lab.activity == .Flow_Course {
        for center,index in witch_ring_positions {
            if !witch_lab.show_course_overview && (index<max(witch_lab.ring_index-1,0) || index>witch_lab.ring_index+2) do continue
            color := index<witch_lab.ring_index ? canvas2d.Color{112,225,155,255} : (index==witch_lab.ring_index ? canvas2d.Color{255,220,92,255} : canvas2d.Color{169,133,220,255})
            radius := index==witch_lab.ring_index ? WITCH_RING_RADIUS : WITCH_RING_RADIUS*.88
            witch_draw_ring(center,witch_ring_direction(index),radius,color)
        }
        witch_draw_ring_pass()
    }
    // Thermal helix and crosswind streamers make forces visible before contact.
    for index in 0..<28 {
        angle := f32(index)*.78+f32(canvas2d.GetTime())*.55
        y := 1+f32(index)*1.5
        p := third_person.Vec3{34+f32(math.cos(f64(angle)))*9,y,58+f32(math.sin(f64(angle)))*9}
        world_tube_between(p,p+third_person.Vec3{0,.85,0},{1,0,0},.12,.12,{113,226,211,190})
    }
    for row in 0..<4 {for column in 0..<7 {
        p := third_person.Vec3{-43+f32(column)*8,3+f32(row)*4,42+f32(row)*3}
        wind := witch_wind_at(p,f32(canvas2d.GetTime()))
        world_tube_between(p,p+wind*.55,{0,1,0},.075,.075,{224,235,190,210})
    }}
    if witch_lab.activity == .Wind_Crossing {
        streamer_positions := [6][2]f32{{-30,35},{0,37},{30,39},{-30,51},{0,53},{30,55}}
        for position in streamer_positions do witch_draw_streamer(position[0],position[1],f32(canvas2d.GetTime()))
    }
    landing_y := witch_ground_height(42,132)+.16
    world_box({42,landing_y,132},{38,.3,27},{199,165,82,255})
    for stripe in -3..=3 do world_box({42+f32(stripe)*5,landing_y+.18,132},{2.4,.08,22},{229,202,115,255})
    if witch_lab.activity == .Wind_Crossing {
        goal_y := witch_ground_height(0,74)
        witch_draw_beacon({0,goal_y,74},{255,213,105,255})
    } else if witch_lab.activity == .Thermal_Landing && !witch_lab.thermal_reached {
        witch_draw_beacon({34,witch_ground_height(34,58),58},{102,221,204,255})
    }
    witch_draw_approaching_wind()
    witch_draw_flight_feedback()
    witch_draw_completion_burst()
    witch_draw_witch()
    if witch_lab.debug {
        p := witch_render_position()
        witch_draw_physics_debug()
        world_tube_between(p,p+witch_lab.broom.wind*.35,{0,1,0},.08,.08,{90,190,255,255})
        world_tube_between(p,p+witch_lab.broom.net_force*.004,{0,1,0},.09,.09,{255,101,93,255})
        for force,index in witch_lab.broom.segment_forces {
            offset := f32(index-1)*1.8
            q := witch_transform({0,0,offset})
            world_tube_between(q,q+force*.004,{0,1,0},.055,.055,{255,222,91,255})
        }
    }
}

witch_rider_state_name :: proc(state: Witch_Rider_State) -> cstring {
    switch state {case .Comfortable:return "COMFORTABLE";case .Bracing:return "BRACING";case .Straining:return "STRAINING";case .Slipping:return "SLIPPING";case .Critical:return "HANGING ON";case .Recovering:return "RECOVERING"}
    return ""
}

witch_activity_name :: proc(activity: Witch_Activity) -> cstring {
    switch activity {case .Flow_Course:return "FLY THE MEADOW CIRCUIT";case .Wind_Crossing:return "CARRY THE PARCEL ACROSS THE WIND";case .Thermal_Landing:return "RIDE THE THERMAL, THEN LAND"}
    return ""
}

witch_activity_status :: proc() -> cstring {
    if witch_lab.broom.rider_state == .Recovering do return "BROOM CATCHING YOU"
    if witch_lab.broom.rider_state == .Critical do return "HOLD ON"
    if witch_lab.activity_complete {
        switch witch_lab.activity {
        case .Flow_Course: return "COURSE COMPLETE"
        case .Wind_Crossing: return witch_lab.parcel_security>.55 ? "PARCEL DELIVERED" : "PARCEL DELIVERED — ROUGH RIDE"
        case .Thermal_Landing: return "THERMAL LANDING COMPLETE"
        }
    }
    if witch_lab.collision_time > 0 do return "STEADY — KEEP FLYING"
    if witch_lab.broom.power<15 do return "GLIDE TO RECOVER POWER"
    if witch_lab.landing_assist>.28 do return "SLOW AND LEVEL"
    if witch_lab.activity == .Flow_Course do return fmt.ctprintf("RING %d OF %d", min(witch_lab.ring_index+1,WITCH_RING_COUNT), WITCH_RING_COUNT)
    if witch_lab.activity == .Wind_Crossing do return fmt.ctprintf("PARCEL %3.0f%% SECURE", witch_lab.parcel_security*100)
    if witch_lab.activity == .Thermal_Landing {
        return witch_lab.thermal_reached ? "LAND ON THE HAY PLATFORM" : "CLIMB ABOVE 24 M IN THE THERMAL"
    }
    return ""
}

witch_context_prompt :: proc() -> cstring {
    if witch_lab.activity_complete do return witch_lab.controller_used ? "A REPLAY" : "F REPLAY   1 2 3 CHOOSE ACTIVITY"
    if witch_lab.broom.rider_state == .Critical || witch_lab.broom.rider_state == .Straining do return witch_lab.controller_used ? "LB BRACE" : "SHIFT BRACE"
    if witch_lab.collision_time > 0 do return witch_lab.controller_used ? "BACK RESET" : "R RESET"
    if witch_lab.broom.power<15 do return witch_lab.controller_used ? "RELEASE RT TO RECOVER" : "RELEASE W TO RECOVER"
    if witch_lab.activity == .Thermal_Landing && witch_lab.thermal_reached do return witch_lab.controller_used ? "LEFT STICK DESCEND   LT BRAKE" : "C DESCEND   S BRAKE"
    return witch_lab.controller_used ? "LEFT STICK FLY   RT BOOST   LT BRAKE" : "A D / ARROWS FLY   W BOOST   S BRAKE"
}

witch_draw_axis_toggle :: proc(bounds: canvas2d.Rectangle,label: cstring,inverted: bool) {
    hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(),bounds)
    fill := inverted ? canvas2d.Color{61,82,96,235} : canvas2d.Color{25,35,45,220}
    if hovered do fill = inverted ? canvas2d.Color{74,98,112,245} : canvas2d.Color{42,53,63,235}
    canvas2d.DrawRectangleRounded(bounds,.16,6,fill)
    canvas2d.DrawRectangleRoundedLinesEx(bounds,.16,6,1,inverted?canvas2d.Color{123,224,207,255}:canvas2d.Color{111,126,142,255})
    state: cstring = inverted ? "REVERSED" : "NORMAL"
    canvas2d.DrawTextEx(canvas2d.Font{},fmt.ctprintf("%s  %s",label,state),{bounds.x+11,bounds.y+8},11,1,{224,231,232,255})
}

witch_draw_activity_button :: proc(index: int,label: cstring) {
    bounds := witch_activity_button_bounds(index)
    selected := int(witch_lab.activity)==index
    hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(),bounds)
    fill := selected ? canvas2d.Color{72,91,77,240} : canvas2d.Color{23,32,42,214}
    if hovered do fill = selected ? canvas2d.Color{86,108,91,248} : canvas2d.Color{43,53,61,232}
    canvas2d.DrawRectangleRounded(bounds,.15,6,fill)
    canvas2d.DrawRectangleRoundedLinesEx(bounds,.15,6,1,selected?canvas2d.Color{177,225,187,255}:canvas2d.Color{102,115,128,240})
    size := canvas2d.MeasureTextEx(canvas2d.Font{},label,11,1)
    canvas2d.DrawTextEx(canvas2d.Font{},label,{bounds.x+(bounds.width-size.x)*.5,bounds.y+9},11,1,{236,233,209,255})
}

witch_lab_draw_ui :: proc(_: ^Editor, width,height: i32) {
    b := &witch_lab.broom
    panel := canvas2d.Rectangle{22,22,430,126}
    canvas2d.DrawRectangleRounded(panel,.1,8,{17,25,39,225})
    canvas2d.DrawRectangleRoundedLinesEx(panel,.1,8,1,{137,119,171,255})
    canvas2d.DrawTextEx(canvas2d.Font{},"WITCH LAB",{38,37},20,1,{246,226,175,255})
    canvas2d.DrawTextEx(canvas2d.Font{},witch_activity_name(witch_lab.activity),{38,69},13,1,{215,222,232,255})
    status := witch_activity_status()
    canvas2d.DrawTextEx(canvas2d.Font{},status,{38,94},12,1,b.grip<.3?canvas2d.Color{255,142,110,255}:canvas2d.Color{139,231,180,255})
    canvas2d.DrawTextEx(canvas2d.Font{},fmt.ctprintf("POWER  %3.0f",b.power),{38,120},11,1,{157,220,218,255})
    canvas2d.DrawRectangleRec({118,122,clamp(b.power/100,0,1)*190,7},{102,213,198,255})
    witch_draw_activity_button(0,"COURSE")
    witch_draw_activity_button(1,"PARCEL")
    witch_draw_activity_button(2,"THERMAL")
    prompt := witch_context_prompt()
    size := canvas2d.MeasureTextEx(canvas2d.Font{},prompt,12,1)
    canvas2d.DrawTextEx(canvas2d.Font{},prompt,{f32(width)*.5-size.x*.5,f32(height)-34},12,1,{245,237,207,255})
    witch_draw_axis_toggle(witch_axis_toggle_bounds(f32(width),false),"HORIZONTAL",witch_lab.invert_horizontal)
    witch_draw_axis_toggle(witch_axis_toggle_bounds(f32(width),true),"VERTICAL",witch_lab.invert_vertical)
    if witch_lab.activity_complete {
        replay_bounds := witch_replay_bounds(f32(width),f32(height))
        hovered := canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(),replay_bounds)
        canvas2d.DrawRectangleRounded(replay_bounds,.18,7,hovered?canvas2d.Color{91,112,98,245}:canvas2d.Color{64,84,75,238})
        canvas2d.DrawRectangleRoundedLinesEx(replay_bounds,.18,7,1,{177,225,187,255})
        label: cstring = "REPLAY ACTIVITY"
        label_size := canvas2d.MeasureTextEx(canvas2d.Font{},label,12,1)
        canvas2d.DrawTextEx(canvas2d.Font{},label,{replay_bounds.x+(replay_bounds.width-label_size.x)*.5,replay_bounds.y+10},12,1,{244,239,205,255})
    }
    if witch_lab.debug {
        ground := witch_ground_height(b.position.x,b.position.z)
        brace: cstring = witch_lab.intent.brace ? "MANUAL" : (b.rider_state==.Bracing ? "AUTO" : "NO")
        debug_lines := [5]cstring{
            fmt.ctprintf("SPEED %.1f  AIR %.1f  ALT %.1f  WIND %.1f %.1f %.1f",witch_length(b.velocity),witch_length(b.velocity-b.wind),b.position.y-ground,b.wind.x,b.wind.y,b.wind.z),
            fmt.ctprintf("INTENT S %.2f  C %.2f  T %.2f  B %.2f",witch_lab.intent.steer,witch_lab.intent.climb,witch_lab.intent.throttle,witch_lab.intent.brake),
            fmt.ctprintf("DES ACC %.1f %.1f %.1f  ACT %.1f %.1f %.1f",b.desired_acceleration.x,b.desired_acceleration.y,b.desired_acceleration.z,b.actual_acceleration.x,b.actual_acceleration.y,b.actual_acceleration.z),
            fmt.ctprintf("POWER %.1f  GRIP %.2f  %s  BRACE %s",b.power,b.grip,witch_rider_state_name(b.rider_state),brace),
            fmt.ctprintf("TORQUE %.1f %.1f %.1f  DT %.4f",b.net_torque.x,b.net_torque.y,b.net_torque.z,WITCH_FIXED_DT),
        }
        canvas2d.DrawRectangleRounded({f32(width)-465,96,443,119},.08,6,{14,19,25,224})
        for line,index in debug_lines do canvas2d.DrawTextEx(canvas2d.Font{},line,{f32(width)-452,108+f32(index)*19},11,1,{207,225,214,255})
    }
}

witch_lab_exit :: proc(_: ^Editor) {witch_lab = {}}

@(test)
witch_wind_is_coherent_and_repeatable :: proc(t: ^testing.T) {
    position := third_person.Vec3{12, 9, 44}
    first := witch_wind_at(position, 3.25)
    second := witch_wind_at(position, 3.25)
    nearby := witch_wind_at(position + third_person.Vec3{.1, 0, .1}, 3.25)
    testing.expect(t, first == second)
    testing.expect(t, witch_length(first-nearby) < .2)
}

@(test)
witch_fixed_step_stays_bounded :: proc(t: ^testing.T) {
    witch_lab = {config = witch_default_config()}
    witch_lab.broom.position = {0, 5, -61}
    witch_lab.broom.yaw = math.PI
    witch_lab.broom.power = 100
    witch_lab.broom.grip = 1
    witch_lab.intent = {throttle = 1, steer = .35, climb = .2}
    for step in 0..<1200 do witch_step(WITCH_FIXED_DT, f32(step)*WITCH_FIXED_DT)
    testing.expect(t, witch_length(witch_lab.broom.velocity) <= 34.01)
    testing.expect(t, witch_lab.broom.position == witch_lab.broom.position)
    testing.expect(t, witch_lab.broom.power >= 0 && witch_lab.broom.power <= 100)
    testing.expect(t, witch_lab.broom.grip >= 0 && witch_lab.broom.grip <= 1)
}

@(test)
witch_tree_impact_is_recoverable :: proc(t: ^testing.T) {
    witch_lab = {config = witch_default_config()}
    tree := witch_trees[0]
    ground := witch_ground_height(tree.x, tree.z)
    witch_lab.broom.position = {tree.x+.2, ground+2, tree.z}
    witch_lab.broom.velocity = {-12, 0, 0}
    witch_lab.broom.grip = 1
    witch_resolve_tree_collisions()
    testing.expect(t, witch_length(third_person.Vec3{witch_lab.broom.position.x-tree.x,0,witch_lab.broom.position.z-tree.z}) >= .65*tree.scale+.54)
    testing.expect(t, witch_lab.broom.velocity.x > -12)
    testing.expect(t, witch_lab.broom.grip > 0)
    testing.expect(t, witch_lab.collision_time > 0)
}

@(test)
witch_activities_complete_from_simulation_state :: proc(t: ^testing.T) {
    witch_lab = {config = witch_default_config(), activity = .Flow_Course, ring_index = WITCH_RING_COUNT-1}
    witch_lab.broom.position = witch_ring_positions[WITCH_RING_COUNT-1]
    witch_update_activity(WITCH_FIXED_DT)
    testing.expect(t, witch_lab.activity_complete)

    witch_lab = {config = witch_default_config(), activity = .Thermal_Landing, thermal_reached = true, landed = true}
    witch_update_activity(WITCH_FIXED_DT)
    testing.expect(t, witch_lab.activity_complete)
}

@(test)
witch_full_stick_has_turn_climb_and_dive_authority :: proc(t: ^testing.T) {
    witch_lab = {config = witch_default_config()}
    witch_lab.broom = {position={0,12,-61},yaw=math.PI,power=100,grip=1}
    start_yaw := witch_lab.broom.yaw
    witch_lab.intent = {steer=1,throttle=1}
    for step in 0..<240 do witch_step(WITCH_FIXED_DT,f32(step)*WITCH_FIXED_DT)
    testing.expectf(t, math.abs(witch_lab.broom.yaw-start_yaw)>.45, "full steer changed heading by only %.3f rad", math.abs(witch_lab.broom.yaw-start_yaw))

    witch_lab = {config = witch_default_config()}
    witch_lab.broom = {position={0,12,-61},yaw=math.PI,power=100,grip=1}
    witch_lab.intent = {climb=1}
    for step in 0..<120 do witch_step(WITCH_FIXED_DT,f32(step)*WITCH_FIXED_DT)
    testing.expectf(t, witch_lab.broom.velocity.y>2.5, "full climb produced only %.2f m/s vertical speed", witch_lab.broom.velocity.y)

    witch_lab = {config = witch_default_config()}
    witch_lab.broom = {position={0,24,-61},yaw=math.PI,power=100,grip=1}
    witch_lab.intent = {climb=-1}
    for step in 0..<120 do witch_step(WITCH_FIXED_DT,f32(step)*WITCH_FIXED_DT)
    testing.expectf(t, witch_lab.broom.velocity.y < -2.5, "full dive produced only %.2f m/s vertical speed", witch_lab.broom.velocity.y)
}

@(test)
witch_assisted_recovery_restores_bounded_grip :: proc(t: ^testing.T) {
    witch_lab = {config=witch_default_config()}
    witch_lab.broom = {position={0,16,-61},yaw=math.PI,power=100,grip=.05,recovery_time=2.2,rider_state=.Recovering}
    for step in 0..<360 do witch_step(WITCH_FIXED_DT,f32(step)*WITCH_FIXED_DT)
    testing.expect(t, witch_lab.broom.recovery_time <= 0)
    testing.expectf(t, witch_lab.broom.grip>.5 && witch_lab.broom.grip<=1, "recovery left grip outside healthy bounds: %.3f", witch_lab.broom.grip)
    testing.expect(t, witch_lab.broom.rider_state != .Critical)
}

@(test)
witch_presentation_interpolates_fixed_states :: proc(t: ^testing.T) {
    witch_lab = {}
    witch_lab.previous_position = {0,2,4}
    witch_lab.broom.position = {10,6,8}
    witch_lab.previous_attitude = {.1,.2,.3}
    witch_lab.broom.pitch = .5
    witch_lab.broom.yaw = .6
    witch_lab.broom.roll = .7
    witch_lab.accumulator = WITCH_FIXED_DT*.5
    testing.expect(t, witch_render_position() == third_person.Vec3{5,4,6})
    attitude := witch_render_attitude()
    testing.expect(t, math.abs(attitude.x-.3)<.0001)
    testing.expect(t, math.abs(attitude.y-.4)<.0001)
    testing.expect(t, math.abs(attitude.z-.5)<.0001)
}

@(test)
witch_terrain_assist_reads_ridge_ahead_and_respects_descent :: proc(t: ^testing.T) {
    position := third_person.Vec3{0,witch_ground_height(0,65)+7,65}
    velocity := third_person.Vec3{0,-1,16}
    assisted := witch_terrain_lookahead_lift(position,velocity,0,12)
    descending := witch_terrain_lookahead_lift(position,velocity,-1,12)
    testing.expectf(t, assisted>20, "ridge look-ahead produced only %.2f N assistance", assisted)
    testing.expectf(t, descending<assisted*.4, "deliberate descent retained too much assistance: %.2f vs %.2f", descending, assisted)
}

@(test)
witch_obstacle_assist_deflects_but_yields_to_player_steer :: proc(t: ^testing.T) {
    tree := witch_trees[1]
    ground := witch_ground_height(tree.x,tree.z)
    position := third_person.Vec3{tree.x+1.2,ground+4,tree.z-8}
    velocity := third_person.Vec3{0,0,12}
    witch_lab.broom.yaw = math.PI
    assisted := witch_obstacle_avoidance_acceleration(position,velocity,0)
    overridden := witch_obstacle_avoidance_acceleration(position,velocity,1)
    testing.expectf(t, witch_length(assisted)>.25, "approaching tree produced only %.3f m/s2 avoidance", witch_length(assisted))
    testing.expectf(t, witch_length(overridden)<witch_length(assisted)*.5, "full steer did not retain authority: %.3f vs %.3f", witch_length(overridden),witch_length(assisted))
}

@(test)
witch_landing_assist_softens_descent_and_allows_go_around :: proc(t: ^testing.T) {
    ground := witch_ground_height(42,132)
    position := third_person.Vec3{42,ground+4,132}
    velocity := third_person.Vec3{5,-7,1}
    assisted := witch_landing_assistance(position,velocity,{},56)
    go_around := witch_landing_assistance(position,velocity,{throttle=1},56)
    testing.expect(t, assisted.factor>.4)
    testing.expectf(t, assisted.lift>100, "landing descent produced only %.2f N lift", assisted.lift)
    testing.expect(t, assisted.drag.x<0)
    testing.expectf(t, go_around.factor<assisted.factor*.2, "throttle did not release landing assist: %.3f vs %.3f", go_around.factor,assisted.factor)
}

@(test)
witch_flow_course_has_forgiving_spacing_and_gates :: proc(t: ^testing.T) {
    testing.expect(t, WITCH_RING_RADIUS>=5.5)
    total_length: f32
    for index in 1..<WITCH_RING_COUNT {
        spacing := witch_length(witch_ring_positions[index]-witch_ring_positions[index-1])
        testing.expectf(t, spacing>18, "rings %d and %d are only %.2f m apart", index,index+1,spacing)
        total_length += spacing
    }
    testing.expectf(t, total_length>450, "circuit is only %.1f m long",total_length)
    testing.expectf(t, len(witch_trees)>=24, "circuit has only %d collision-backed obstacles",len(witch_trees))
}

@(test)
witch_course_gates_face_the_route :: proc(t: ^testing.T) {
    for index in 0..<WITCH_RING_COUNT {
        direction := witch_ring_direction(index)
        testing.expectf(t,math.abs(witch_length(direction)-1)<.001,"gate %d direction was not normalized",index+1)
        testing.expectf(t,math.abs(direction.y)<.001,"gate %d tilted out of its readable vertical plane",index+1)
        if index+1<WITCH_RING_COUNT {
            route := witch_ring_positions[index+1]-witch_ring_positions[index]
            route.y = 0
            // The gate normal may average incoming and outgoing legs, but it
            // must never face backward relative to the next target.
            testing.expectf(t,direction.x*route.x+direction.z*route.z>=0,"gate %d faced away from the route",index+1)
        }
    }
}

@(test)
witch_pose_communicates_acceleration_braking_and_crosswind :: proc(t: ^testing.T) {
    broom := Witch_Broom_State{yaw=0,wind={10,0,0},power=100,rider_state=.Comfortable}
    acceleration := witch_pose_parameters(broom,{throttle=1},0)
    braking := witch_pose_parameters(broom,{brake=1},0)
    landing := witch_pose_parameters(broom,{},1)
    broom.power = 0
    exhausted := witch_pose_parameters(broom,{},0)
    testing.expect(t, acceleration.crouch>.1)
    testing.expect(t, acceleration.torso_fore_aft>0)
    testing.expect(t, braking.torso_fore_aft<0 && braking.head_fore_aft<braking.torso_fore_aft)
    testing.expect(t, acceleration.lean>.2)
    testing.expect(t, landing.crouch>.1)
    testing.expect(t, exhausted.strain>.7 && exhausted.crouch>.1)
}

@(test)
witch_starfox_controls_cruise_boost_and_brake :: proc(t: ^testing.T) {
    cruise := witch_propulsion_input({},.42)
    boost := witch_propulsion_input({throttle=1},.42)
    brake := witch_propulsion_input({brake=1},.42)
    testing.expectf(t, cruise>.35 && cruise<.5,"neutral cruise was %.2f",cruise)
    testing.expectf(t, boost>.99,"boost only reached %.2f",boost)
    testing.expectf(t, brake<.01,"brake left %.2f propulsion",brake)
}

@(test)
witch_neutral_cruise_advances_and_brake_slows :: proc(t: ^testing.T) {
    witch_lab = {config=witch_default_config(),activity=.Flow_Course}
    witch_lab.broom.position = {0,40,-60}
    witch_lab.broom.yaw = math.PI
    witch_lab.broom.power = 100
    witch_lab.broom.grip = 1
    start_z := witch_lab.broom.position.z
    for step in 0..<240 do witch_step(WITCH_FIXED_DT,f32(step)*WITCH_FIXED_DT)
    cruise_speed := witch_length(witch_lab.broom.velocity)
    testing.expectf(t,witch_lab.broom.position.z>start_z+7,"neutral cruise advanced only %.2f m",witch_lab.broom.position.z-start_z)
    testing.expectf(t,cruise_speed>6,"neutral cruise reached only %.2f m/s",cruise_speed)
    witch_lab.intent.brake = 1
    for step in 0..<120 do witch_step(WITCH_FIXED_DT,2+f32(step)*WITCH_FIXED_DT)
    braking_speed := witch_length(witch_lab.broom.velocity)
    testing.expectf(t,braking_speed<cruise_speed*.7,"braking only reduced speed from %.2f to %.2f m/s",cruise_speed,braking_speed)
}

@(test)
witch_exhaustion_keeps_control_and_causes_only_a_gentle_sink :: proc(t: ^testing.T) {
    witch_lab = {config=witch_default_config(),activity=.Flow_Course}
    witch_lab.config.power_recovery = 0
    witch_lab.broom = {position={0,40,-60},velocity={0,0,10},yaw=math.PI,power=0,grip=1}
    witch_lab.intent.throttle = 1
    for step in 0..<240 do witch_step(WITCH_FIXED_DT,f32(step)*WITCH_FIXED_DT)
    testing.expectf(t,witch_lab.broom.velocity.y<-.2 && witch_lab.broom.velocity.y>-3,"exhaustion vertical speed was %.2f m/s",witch_lab.broom.velocity.y)
    testing.expectf(t,witch_lab.broom.velocity.z>10,"exhausted broom lost forward control at %.2f m/s",witch_lab.broom.velocity.z)
    testing.expectf(t,witch_lab.broom.power==0,"exhausted power unexpectedly reached %.2f",witch_lab.broom.power)
}

@(test)
witch_arcade_turn_banks_changes_heading_and_settles :: proc(t: ^testing.T) {
    witch_lab = {config=witch_default_config(),activity=.Flow_Course}
    witch_lab.broom = {position={0,40,-60},velocity={0,0,12},yaw=math.PI,power=100,grip=1}
    start_yaw := witch_lab.broom.yaw
    witch_lab.intent.steer = .65
    for step in 0..<120 do witch_step(WITCH_FIXED_DT,f32(step)*WITCH_FIXED_DT)
    turn := math.abs(witch_angle_delta(witch_lab.broom.yaw,start_yaw))
    testing.expectf(t,turn>.35 && turn<1.05,"moderate one-second turn changed heading %.2f rad",turn)
    testing.expectf(t,math.abs(witch_lab.broom.roll)>.12 && math.abs(witch_lab.broom.roll)<.75,"turn bank reached %.2f rad",witch_lab.broom.roll)
    testing.expectf(t,witch_lab.broom.position.x<-.8,"left turn moved only %.2f m left",witch_lab.broom.position.x)

    witch_lab.intent.steer = 0
    for step in 0..<120 do witch_step(WITCH_FIXED_DT,1+f32(step)*WITCH_FIXED_DT)
    testing.expectf(t,math.abs(witch_lab.broom.roll)<.16,"released turn retained %.2f rad bank",witch_lab.broom.roll)
    testing.expectf(t,math.abs(witch_lab.broom.angular_velocity.y)<.22,"released turn retained %.2f rad/s yaw",witch_lab.broom.angular_velocity.y)
}

@(test)
witch_chase_camera_dodges_tree_obstructions :: proc(t: ^testing.T) {
    tree := witch_trees[0]
    y := witch_ground_height(tree.x,tree.z)+5.2*tree.scale
    follow := third_person.Vec3{tree.x,y,tree.z+10}
    obstructed_eye := third_person.Vec3{tree.x,y,tree.z-10}
    corrected := witch_camera_avoid_trees(follow,obstructed_eye)
    testing.expectf(t,math.abs(corrected.x-obstructed_eye.x)>3,"camera dodged only %.2f m sideways",math.abs(corrected.x-obstructed_eye.x))
    testing.expectf(t,witch_length(corrected-follow)>witch_length(obstructed_eye-follow)*.75,"camera collapsed to %.2f m from rider",witch_length(corrected-follow))

    clear_eye := third_person.Vec3{tree.x+15,y,tree.z+10}
    clear := witch_camera_avoid_trees(follow,clear_eye)
    testing.expectf(t,witch_length(clear-clear_eye)<.001,"clear camera path moved by %.3f m",witch_length(clear-clear_eye))
}

@(test)
witch_stick_axes_correct_quickly_and_recenter_velocity :: proc(t: ^testing.T) {
    witch_lab = {config=witch_default_config(),activity=.Flow_Course}
    witch_lab.broom = {position={0,40,-60},velocity={0,0,12},yaw=math.PI,power=100,grip=1}
    witch_lab.intent.steer = .6
    for step in 0..<60 do witch_step(WITCH_FIXED_DT,f32(step)*WITCH_FIXED_DT)
    testing.expectf(t,witch_lab.broom.position.x<-.55,"half-second horizontal correction moved only %.2f m",witch_lab.broom.position.x)
    witch_lab.intent.steer = 0
    for step in 0..<120 do witch_step(WITCH_FIXED_DT,.5+f32(step)*WITCH_FIXED_DT)
    right := witch_right(witch_lab.broom.yaw)
    lateral_speed := witch_lab.broom.velocity.x*right.x+witch_lab.broom.velocity.z*right.z
    testing.expectf(t,math.abs(lateral_speed)<1.2,"released horizontal input retained %.2f m/s side slip",lateral_speed)

    witch_lab = {config=witch_default_config(),activity=.Flow_Course}
    witch_lab.broom = {position={0,40,-60},velocity={0,0,12},yaw=math.PI,power=100,grip=1}
    witch_lab.intent.climb = .6
    for step in 0..<60 do witch_step(WITCH_FIXED_DT,f32(step)*WITCH_FIXED_DT)
    testing.expectf(t,witch_lab.broom.velocity.y>3,"half-second vertical correction reached only %.2f m/s",witch_lab.broom.velocity.y)
    witch_lab.intent.climb = 0
    for step in 0..<120 do witch_step(WITCH_FIXED_DT,.5+f32(step)*WITCH_FIXED_DT)
    testing.expectf(t,math.abs(witch_lab.broom.velocity.y)<1.2,"released vertical input retained %.2f m/s",witch_lab.broom.velocity.y)
}

@(test)
witch_left_stick_axis_options_reverse_independently :: proc(t: ^testing.T) {
    steer,climb := witch_map_left_stick(.6,-.4,false,false)
    testing.expect(t,steer==.6 && climb==.4)
    steer,climb = witch_map_left_stick(.6,-.4,true,false)
    testing.expect(t,steer==-.6 && climb==.4)
    steer,climb = witch_map_left_stick(.6,-.4,false,true)
    testing.expect(t,steer==.6 && climb==-.4)
    steer,climb = witch_map_left_stick(.6,-.4,true,true)
    testing.expect(t,steer==-.6 && climb==-.4)
    witch_lab = {config=witch_default_config(),activity=.Flow_Course,invert_horizontal=true,invert_vertical=true}
    witch_reset()
    testing.expect(t,witch_lab.invert_horizontal && witch_lab.invert_vertical)
}

@(test)
witch_upcoming_crosswind_warns_before_entry :: proc(t: ^testing.T) {
    warning,side := witch_upcoming_wind({-18,11,26},math.PI,0,.Wind_Crossing)
    calm,_ := witch_upcoming_wind({-80,11,-80},math.PI,0,.Wind_Crossing)
    testing.expectf(t,warning>.75,"crosswind approach warning was only %.2f",warning)
    testing.expectf(t,math.abs(side)>5,"crosswind side cue was only %.2f m/s",side)
    testing.expectf(t,calm<warning*.4,"calm-air warning %.2f was too close to crosswind %.2f",calm,warning)
}

@(test)
witch_completion_replay_is_immediate_and_preserves_options :: proc(t: ^testing.T) {
    witch_lab = {
        config=witch_default_config(),activity=.Flow_Course,activity_complete=true,
        invert_horizontal=true,invert_vertical=true,
    }
    witch_update_activity(.5)
    testing.expectf(t,witch_lab.completion_time==.5,"completion acknowledgement advanced %.2f s",witch_lab.completion_time)
    witch_activity_start(.Flow_Course)
    testing.expect(t,!witch_lab.activity_complete && witch_lab.ring_index==0)
    testing.expect(t,witch_lab.invert_horizontal && witch_lab.invert_vertical)
    bounds := witch_replay_bounds(1280,720)
    testing.expect(t,bounds.x>0 && bounds.y>0 && bounds.x+bounds.width<1280 && bounds.y+bounds.height<720)
}

@(test)
witch_activity_selection_cycles_and_exposes_three_distinct_buttons :: proc(t: ^testing.T) {
    testing.expect(t,witch_activity_offset(.Flow_Course,-1)==.Thermal_Landing)
    testing.expect(t,witch_activity_offset(.Flow_Course,1)==.Wind_Crossing)
    testing.expect(t,witch_activity_offset(.Thermal_Landing,1)==.Flow_Course)
    previous_right := f32(-1)
    for index in 0..<3 {
        bounds := witch_activity_button_bounds(index)
        testing.expectf(t,bounds.width>=120 && bounds.height>=28,"activity button %d was too small",index)
        testing.expectf(t,bounds.x>previous_right,"activity button %d overlapped its neighbor",index)
        previous_right = bounds.x+bounds.width
    }
}

@(test)
witch_ring_pass_feedback_starts_at_crossed_gate_and_expires :: proc(t: ^testing.T) {
    witch_lab = {config=witch_default_config(),activity=.Flow_Course}
    witch_lab.broom.position = witch_ring_positions[0]
    witch_update_activity(WITCH_FIXED_DT)
    testing.expect(t,witch_lab.ring_index==1)
    testing.expect(t,witch_lab.ring_pass_position==witch_ring_positions[0])
    testing.expectf(t,witch_lab.ring_pass_time>.6,"ring feedback started with only %.2f s",witch_lab.ring_pass_time)
    witch_lab.broom.position = {200,40,200}
    witch_update_activity(.7)
    testing.expect(t,witch_lab.ring_pass_time==0)
}
