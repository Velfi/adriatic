package plazas

import "core:math"

MAX_PAVING_PIECES :: 96

Paving_Kind :: enum u8 {
    Field,
    Border,
    Mosaic,
    Inlay,
}

Paving_Piece :: struct {
    x, z:          f32,
    width, length: f32,
    rotation:      f32,
    kind:          Paving_Kind,
    tone:          u8,
}

Plan :: struct {
    seed:          u32,
    width, length: f32,
    paving:        [MAX_PAVING_PIECES]Paving_Piece,
    paving_count:  int,
    pattern:       u8,
    valid:         bool,
}

mix :: proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * u32(0x7feb352d)
    result = (result ~ (result >> 15)) * u32(0x846ca68b)
    return result ~ (result >> 16)
}

append_paving :: proc(plan: ^Plan, piece: Paving_Piece) {
    if plan.paving_count >= len(plan.paving) do return
    plan.paving[plan.paving_count] = piece
    plan.paving_count += 1
}

generate :: proc(seed: u32, requested_width, requested_length: f32) -> Plan {
    plan := Plan {
        seed    = seed,
        width   = max(requested_width, f32(10)),
        length  = max(requested_length, f32(8)),
        pattern = u8(mix(seed) % 3),
    }

    // A pale field, a contrasting stone frame, and a rotated central mosaic
    // form the paving grammar. All pieces remain inside the circulation area.
    append_paving(&plan, {width = plan.width, length = plan.length, kind = .Field})
    border := clamp(min(plan.width, plan.length) * .055, f32(.55), f32(1.1))
    append_paving(&plan, {z = -plan.length * .5 + border * .5, width = plan.width, length = border, kind = .Border})
    append_paving(&plan, {z = plan.length * .5 - border * .5, width = plan.width, length = border, kind = .Border})
    append_paving(
        &plan,
        {x = -plan.width * .5 + border * .5, width = border, length = plan.length - border * 2, kind = .Border},
    )
    append_paving(
        &plan,
        {x = plan.width * .5 - border * .5, width = border, length = plan.length - border * 2, kind = .Border},
    )

    // The interior deliberately avoids a road-like regular grid. Depending on
    // the seed it becomes a broken compass rose, a drifting woven field, or a
    // set of eccentric archaeological-looking bands.
    mosaic_radius := clamp(min(plan.width, plan.length) * .34, f32(2.8), f32(6.2))
    spoke_count := 16
    for spoke in 0 ..< spoke_count {
        angle := f32(spoke) * f32(math.PI * 2) / f32(spoke_count)
        hash := mix(seed ~ u32(spoke) * u32(0x9e3779b9))
        jitter := f32(hash & 255) / 255
        radius := mosaic_radius * (.28 + jitter * .48)
        piece_rotation := angle
        piece_width := mosaic_radius * (.34 + jitter * .26)
        piece_length := mosaic_radius * (.10 + f32((hash >> 8) & 255) / 255 * .10)
        if plan.pattern == 1 {
            piece_rotation = (spoke % 2 == 0 ? f32(.72) : f32(-.72)) + angle * .18
            radius = mosaic_radius * (.18 + f32(spoke % 5) * .13)
        } else if plan.pattern == 2 {
            piece_rotation = angle + f32(math.PI * .5)
            radius = mosaic_radius * (.22 + f32(spoke % 4) * .18)
            piece_width *= 1.22
        }
        append_paving(&plan, {
            x        = f32(math.cos(f64(angle))) * radius,
            z        = f32(math.sin(f64(angle))) * radius,
            width    = piece_width,
            length   = piece_length,
            rotation = piece_rotation,
            kind     = .Mosaic,
            tone     = u8((spoke + int(hash >> 16)) % 3),
        })
    }
    // Off-center fragments make the covering feel accumulated and repaired,
    // rather than stamped from a perfectly symmetrical civic-road kit.
    for patch in 0 ..< 9 {
        hash := mix(seed ~ u32(patch + 101) * u32(0x85ebca6b))
        unit_x := f32(hash & 1023) / 1023
        unit_z := f32((hash >> 10) & 1023) / 1023
        append_paving(&plan, {
            x        = (unit_x - .5) * (plan.width - border * 5),
            z        = (unit_z - .5) * (plan.length - border * 5),
            width    = .55 + f32((hash >> 20) & 7) * .16,
            length   = 1.2 + f32((hash >> 23) & 7) * .24,
            rotation = f32(hash % 628) * .01,
            kind     = .Inlay,
            tone     = u8((hash >> 29) % 3),
        })
    }

    plan.valid = validate(&plan)
    return plan
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil || plan.width < 10 || plan.length < 8 do return false
    if plan.paving_count < 20 do return false
    for piece in plan.paving[:plan.paving_count] {
        if piece.width <= 0 || piece.length <= 0 do return false
        cosine, sine := math.abs(math.cos(piece.rotation)), math.abs(math.sin(piece.rotation))
        reach_x := (piece.width * cosine + piece.length * sine) * .5
        reach_z := (piece.width * sine + piece.length * cosine) * .5
        if math.abs(piece.x) + reach_x > plan.width * .5 + .01 do return false
        if math.abs(piece.z) + reach_z > plan.length * .5 + .01 do return false
    }
    return true
}
