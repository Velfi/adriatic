package vehicles

import third_person "../../packages/third_person"
import "core:math"

// The occupancy layer deliberately has no physics dependency. The game owns
// collision queries, then calls try_exit with whether the door-side spot is
// safe. This keeps the GTA-style interaction usable by cars, boats, and VTOLs.
Occupancy_Mode :: enum {
    On_Foot,
    Driving,
}

Character :: struct {
    position:           third_person.Vec3,
    facing_yaw_radians: f32,
    mode:               Occupancy_Mode,
    vehicle:            ^Vehicle,
}

Vehicle :: struct {
    position:           third_person.Vec3,
    yaw_radians:        f32,
    interaction_radius: f32,
    exit_distance:      f32,
    locked:             bool,
    driver:             ^Character,
}

default_vehicle :: proc(position: third_person.Vec3) -> Vehicle {
    return {position = position, interaction_radius = 2.5, exit_distance = 1.8}
}

// try_enter_nearest seats an on-foot character in the closest unlocked,
// unoccupied vehicle in range. A caller can use the returned pointer to switch
// its input routing from character movement to vehicle controls.
try_enter_nearest :: proc(character: ^Character, vehicles: []^Vehicle) -> (vehicle: ^Vehicle, entered: bool) {
    if character == nil || character.mode != .On_Foot do return
    closest_distance_squared := f32(0)
    for candidate in vehicles {
        if candidate == nil || candidate.locked || candidate.driver != nil do continue
        delta := subtract(character.position, candidate.position)
        distance_squared := dot(delta, delta)
        radius := candidate.interaction_radius
        if radius <= 0 do radius = 2.5
        if distance_squared > radius * radius do continue
        if !entered || distance_squared < closest_distance_squared {
            vehicle = candidate
            closest_distance_squared = distance_squared
            entered = true
        }
    }
    if !entered do return
    vehicle.driver = character
    character.vehicle = vehicle
    character.mode = .Driving
    sync_driver(character)
    return
}

// sync_driver keeps the hidden on-foot character seated at the vehicle. Call
// after the vehicle physics step, before deriving the third-person camera.
sync_driver :: proc(character: ^Character) {
    if character == nil || character.mode != .Driving || character.vehicle == nil do return
    character.position = character.vehicle.position
    character.facing_yaw_radians = character.vehicle.yaw_radians
}

// try_exit places the driver beside the left door. Pass false when the product
// collision query finds an obstacle there; in that case the driver stays seated.
try_exit :: proc(character: ^Character, exit_position_clear: bool) -> (exited: bool) {
    if character == nil || character.mode != .Driving || character.vehicle == nil || !exit_position_clear do return
    vehicle := character.vehicle
    distance := vehicle.exit_distance
    if distance <= 0 do distance = 1.8
    left := third_person.Vec3 {
        x = -math.cos(vehicle.yaw_radians),
        z = math.sin(vehicle.yaw_radians),
    }
    character.position = add(vehicle.position, scale(left, distance))
    character.facing_yaw_radians = vehicle.yaw_radians
    character.vehicle = nil
    character.mode = .On_Foot
    vehicle.driver = nil
    return true
}

subtract :: proc(a, b: third_person.Vec3) -> third_person.Vec3 { return {a.x - b.x, a.y - b.y, a.z - b.z} }
add :: proc(a, b: third_person.Vec3) -> third_person.Vec3 { return {a.x + b.x, a.y + b.y, a.z + b.z} }
scale :: proc(value: third_person.Vec3, amount: f32) -> third_person.Vec3 {return{
        value.x * amount,
        value.y * amount,
        value.z * amount,
    }}
dot :: proc(a, b: third_person.Vec3) -> f32 { return a.x * b.x + a.y * b.y + a.z * b.z }
