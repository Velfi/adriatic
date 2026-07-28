package kiosks

import "core:math"

Vec2 :: [2]f32

KIOSK_SIDE_X :: f32(1.52)
KIOSK_SIDE_Z :: f32(.42)
KIOSK_SIDE_WIDTH :: f32(.16)
KIOSK_SIDE_DEPTH :: f32(2.35)
KIOSK_REAR_Z :: f32(1.58)
KIOSK_REAR_WIDTH :: f32(3.2)
KIOSK_REAR_DEPTH :: f32(.16)
KIOSK_COUNTER_Z :: f32(-.535)
KIOSK_COUNTER_WIDTH :: f32(3)
KIOSK_COUNTER_DEPTH :: f32(.49)

Box :: struct {
    center: Vec2,
    width:  f32,
    depth:  f32,
}

// resolve_circle keeps a world-space circle outside the kiosk's solid walls
// and service counter. The front approach and apron deliberately remain open.
resolve_circle :: proc(center, position: Vec2, radius: f32) -> (Vec2, bool) {
    if radius < 0 do return position, false
    boxes := [4]Box {
        {{center.x - KIOSK_SIDE_X, center.y + KIOSK_SIDE_Z}, KIOSK_SIDE_WIDTH, KIOSK_SIDE_DEPTH},
        {{center.x + KIOSK_SIDE_X, center.y + KIOSK_SIDE_Z}, KIOSK_SIDE_WIDTH, KIOSK_SIDE_DEPTH},
        {{center.x, center.y + KIOSK_REAR_Z}, KIOSK_REAR_WIDTH, KIOSK_REAR_DEPTH},
        {{center.x, center.y + KIOSK_COUNTER_Z}, KIOSK_COUNTER_WIDTH, KIOSK_COUNTER_DEPTH},
    }

    result := position
    collided := false
    // The counter meets the side walls. A few passes settle corner overlaps.
    for _ in 0 ..< 3 {
        changed := false
        for box in boxes {
            local_x := result.x - box.center.x
            local_z := result.y - box.center.y
            half_x := box.width * .5 + radius
            half_z := box.depth * .5 + radius
            if math.abs(local_x) >= half_x || math.abs(local_z) >= half_z do continue

            distance_x := half_x - math.abs(local_x)
            distance_z := half_z - math.abs(local_z)
            if distance_x < distance_z {
                local_x = local_x < 0 ? -half_x : half_x
            } else {
                local_z = local_z < 0 ? -half_z : half_z
            }
            result = {box.center.x + local_x, box.center.y + local_z}
            changed, collided = true, true
        }
        if !changed do break
    }
    return result, collided
}
