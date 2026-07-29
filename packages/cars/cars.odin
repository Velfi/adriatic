package cars

import "core:math"

// Compact civilian cars are generated from a small set of proportions rather
// than stored as authored models. Dimensions are in metres and deliberately
// favour the narrow tracks, tall cabins, small wheels, and short overhangs of
// late-1930s and 1940s European utility cars.

Kind :: enum u8 {
    Sedan,
    Coupe,
    Pickup,
    Delivery,
    Woody,
}

Palette :: enum u8 {
    Sage,
    Cream,
    Oxblood,
    Petrol,
    Mustard,
}

Plan :: struct {
    kind:          Kind,
    palette:       Palette,
    length:        f32,
    width:         f32,
    belt_height:   f32,
    cabin_height:  f32,
    cabin_length:  f32,
    cabin_offset:  f32,
    wheelbase:     f32,
    wheel_radius:  f32,
    wheel_width:   f32,
    hood_length:   f32,
    fender_radius: f32,
}

Part :: enum u8 {
    Body,
    Glass,
    Trim,
    Timber,
    Tire,
    Whitewall,
    Chrome,
}

Vertex :: struct {
    position: [3]f32,
    part:     Part,
}

MESH_VERTEX_CAPACITY :: 1536
MESH_INDEX_CAPACITY :: 4096

// Vertices are welded within a material region.  Body-to-glass seams retain
// separate vertices so parts can be rendered independently, while adjacent
// body or glass faces share the station vertices that define their topology.
Mesh :: struct {
    vertices:     [MESH_VERTEX_CAPACITY]Vertex,
    vertex_count: int,
    indices:      [MESH_INDEX_CAPACITY]u16,
    index_count:  int,
}

vertices :: proc(mesh: ^Mesh) -> []Vertex {
    if mesh == nil do return nil
    return mesh.vertices[:mesh.vertex_count]
}

triangle :: proc(mesh: ^Mesh, a, b, c: [3]f32, part: Part) {
    if mesh == nil || mesh.index_count + 3 > len(mesh.indices) do return
    positions := [3][3]f32{a, b, c}
    for position in positions {
        found := -1
        for vertex, index in mesh.vertices[:mesh.vertex_count] {
            if vertex.part == part && vertex.position == position {
                found = index
                break
            }
        }
        if found < 0 {
            if mesh.vertex_count >= len(mesh.vertices) do return
            found = mesh.vertex_count
            mesh.vertices[mesh.vertex_count] = {position, part}
            mesh.vertex_count += 1
        }
        mesh.indices[mesh.index_count] = u16(found)
        mesh.index_count += 1
    }
}

quad :: proc(mesh: ^Mesh, a, b, c, d: [3]f32, part: Part) {
    triangle(mesh, a, b, c, part)
    triangle(mesh, a, c, d, part)
}

box :: proc(mesh: ^Mesh, center, size: [3]f32, part: Part) {
    x, y, z := center[0], center[1], center[2]
    hx, hy, hz := size[0] * .5, size[1] * .5, size[2] * .5
    p := [8][3]f32 {
        {x - hx, y - hy, z - hz}, {x + hx, y - hy, z - hz},
        {x + hx, y - hy, z + hz}, {x - hx, y - hy, z + hz},
        {x - hx, y + hy, z - hz}, {x + hx, y + hy, z - hz},
        {x + hx, y + hy, z + hz}, {x - hx, y + hy, z + hz},
    }
    quad(mesh, p[0], p[4], p[5], p[1], part)
    quad(mesh, p[3], p[2], p[6], p[7], part)
    quad(mesh, p[0], p[3], p[7], p[4], part)
    quad(mesh, p[1], p[5], p[6], p[2], part)
    quad(mesh, p[4], p[7], p[6], p[5], part)
    quad(mesh, p[0], p[1], p[2], p[3], part)
}

wheel_disc :: proc(
    mesh: ^Mesh,
    x, y, z, radius, outward: f32,
    part: Part,
) {
    SEGMENTS :: 12
    center := [3]f32{x, y, z}
    for segment in 0 ..< SEGMENTS {
        angle_a := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        angle_b := f32(segment + 1) * math.PI * 2 / f32(SEGMENTS)
        a := [3]f32{x, y + math.cos(angle_a) * radius, z + math.sin(angle_a) * radius}
        b := [3]f32{x, y + math.cos(angle_b) * radius, z + math.sin(angle_b) * radius}
        if outward > 0 {
            triangle(mesh, center, a, b, part)
        } else {
            triangle(mesh, center, b, a, part)
        }
    }
}

wheel :: proc(
    mesh: ^Mesh,
    x, y, z, half_width, radius, outward: f32,
) {
    SEGMENTS :: 12
    inner_x := x - outward * half_width
    outer_x := x + outward * half_width
    inner_center := [3]f32{inner_x, y, z}
    outer_center := [3]f32{outer_x, y, z}
    for segment in 0 ..< SEGMENTS {
        angle_a := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        angle_b := f32(segment + 1) * math.PI * 2 / f32(SEGMENTS)
        ay, az := y + math.cos(angle_a) * radius, z + math.sin(angle_a) * radius
        by, bz := y + math.cos(angle_b) * radius, z + math.sin(angle_b) * radius
        inner_a, inner_b := [3]f32{inner_x, ay, az}, [3]f32{inner_x, by, bz}
        outer_a, outer_b := [3]f32{outer_x, ay, az}, [3]f32{outer_x, by, bz}
        quad(mesh, inner_a, outer_a, outer_b, inner_b, .Tire)
        if outward > 0 {
            triangle(mesh, inner_center, inner_b, inner_a, .Tire)
            triangle(mesh, outer_center, outer_a, outer_b, .Tire)
        } else {
            triangle(mesh, inner_center, inner_a, inner_b, .Tire)
            triangle(mesh, outer_center, outer_b, outer_a, .Tire)
        }
    }
    face_x := outer_x + outward * .004
    wheel_disc(mesh, face_x, y, z, radius * .68, outward, .Whitewall)
    wheel_disc(mesh, face_x + outward * .004, y, z, radius * .32, outward, .Chrome)
}

kind_name :: proc(kind: Kind) -> string {
    switch kind {
    case .Sedan: return "40s SEDAN"
    case .Coupe: return "SPORT COUPE"
    case .Pickup: return "MARKET PICKUP"
    case .Delivery: return "DELIVERY VAN"
    case .Woody: return "WOODY ESTATE"
    }
    return "CAR"
}

seed_variation :: proc(seed: u32, shift: u32, scale: f32) -> f32 {
    mixed := seed + u32(0x9e3779b9)
    mixed = (mixed ~ (mixed >> 16)) * u32(0x7feb352d)
    mixed = (mixed ~ (mixed >> 15)) * u32(0x846ca68b)
    mixed ~= mixed >> 16
    step := i32((mixed >> shift) & 7) - 3
    return f32(step) * scale
}

// generate is deterministic: the same kind and seed always yield the same car.
// Seed variation is intentionally restrained so every output remains plausible.
generate :: proc(kind: Kind, seed: u32) -> Plan {
    plan := Plan {
        kind          = kind,
        palette       = Palette(seed % u32(len(Palette))),
        length        = 3.55,
        width         = 1.43,
        belt_height   = .82,
        cabin_height  = .72,
        cabin_length  = 1.62,
        cabin_offset  = .10,
        wheelbase     = 2.18,
        wheel_radius  = .31,
        wheel_width   = .16,
        hood_length   = .88,
        fender_radius = .39,
    }
    variation := f32(i32((seed >> 5) % 9) - 4) * .025
    plan.length += variation
    plan.width += variation * .25
    switch kind {
    case .Sedan:
    case .Coupe:
        plan.length = 3.42 + variation
        plan.cabin_length = 1.48
        plan.cabin_offset = -.04
        plan.cabin_height = .60
        plan.hood_length = 1.02
    case .Pickup:
        plan.length = 3.78 + variation
        plan.cabin_length = 1.06
        plan.cabin_offset = -.43
        plan.cabin_height = .68
        plan.wheelbase = 2.34
    case .Delivery:
        plan.length = 3.68 + variation
        plan.cabin_length = 2.15
        plan.cabin_offset = .20
        plan.cabin_height = .91
        plan.belt_height = .84
        plan.wheelbase = 2.28
    case .Woody:
        plan.length = 3.72 + variation
        plan.cabin_length = 2.02
        plan.cabin_offset = .18
        plan.cabin_height = .76
        plan.wheelbase = 2.26
    }
    // Independent, quantized proportion channels make a seed change visible in
    // silhouette while retaining the small, upright European family envelope.
    plan.wheel_radius = clamp(plan.wheel_radius + seed_variation(seed, 3, .006), f32(.29), f32(.34))
    plan.wheelbase += seed_variation(seed, 6, .018)
    plan.belt_height += seed_variation(seed, 9, .010)
    plan.cabin_height = clamp(
        plan.cabin_height + seed_variation(seed, 12, .012),
        f32(.60),
        f32(.94),
    )
    plan.cabin_length += seed_variation(seed, 15, .020)
    plan.hood_length += seed_variation(seed, 18, .015)
    plan.wheelbase = clamp(plan.wheelbase, plan.length * .55, plan.length * .67)
    plan.fender_radius = plan.wheel_radius * 1.26
    return plan
}

// body_ring describes a rounded eight-point transverse section. Stations at
// the axles raise the lower corners, so the continuous side topology forms
// wheel-arch openings instead of hiding wheels behind an unbroken slab.
body_ring :: proc(width, bottom_y, shoulder_y, crown_y, z: f32) -> [8][3]f32 {
    half := width * .5
    return {
        {-half * .72, bottom_y, z},
        {-half, bottom_y + .09, z},
        {-half, shoulder_y, z},
        {-half * .72, crown_y, z},
        {half * .72, crown_y, z},
        {half, shoulder_y, z},
        {half, bottom_y + .09, z},
        {half * .72, bottom_y, z},
    }
}

mesh :: proc(plan: Plan) -> Mesh {
    result: Mesh
    // Put several rings through each wheel opening.  The older coarse loft had
    // one raised ring at an axle, which read as a triangular bite in the sill.
    // These rings follow the arch continuously and give the adjoining fender
    // enough longitudinal topology to turn over the tyre.
    STATIONS :: 21
    axle_t := plan.wheelbase * .5 / plan.length
    arch_t := plan.wheel_radius * 1.18 / plan.length
    station_t := [STATIONS]f32 {
        -.50, -.46,
        -axle_t - arch_t, -axle_t - arch_t * .55, -axle_t, -axle_t + arch_t * .55, -axle_t + arch_t,
        -.16, -.05, .06, .16,
        axle_t - arch_t, axle_t - arch_t * .55, axle_t, axle_t + arch_t * .55, axle_t + arch_t,
        .39, .44, .47, .49, .50,
    }
    rings: [STATIONS][8][3]f32
    for t, index in station_t {
        z := t * plan.length
        arch_distance := min(
            abs(z + plan.wheelbase * .5),
            abs(z - plan.wheelbase * .5),
        )
        arch_amount := clamp(1 - arch_distance / (plan.wheel_radius * 1.18), f32(0), f32(1))
        bottom_y := .20 + arch_amount * (plan.wheel_radius * 1.02 - .20)

        // Pinched extremities and proud haunches produce the narrow, upright
        // coachwork of small pre-war European cars without separate body boxes.
        width_factor := f32(1)
        if t < -.39 do width_factor = .48 + (t + .50) / .11 * .48
        if t > .39 do width_factor = .96 - (t - .39) / .11 * .52
        width_factor += arch_amount * .08

        // The bonnet falls toward the nose; the rear deck treatment changes by
        // family but stays part of the same longitudinal skin.
        crown := f32(.78)
        if t < -.20 do crown = .66 + (t + .50) / .30 * .18
        if t > .30 {
            crown = .78 - (t - .30) / .20 * .18
            if plan.kind == .Delivery || plan.kind == .Woody do crown += .10
            if plan.kind == .Pickup do crown = .66
        }
        if plan.kind == .Coupe && t > .20 {
            crown = .78 - (t - .20) / .30 * .22
        }
        shoulder := min(crown - .10, f32(.68))
        rings[index] = body_ring(plan.width * width_factor, bottom_y, shoulder, crown, z)
    }
    for station in 0 ..< STATIONS - 1 {
        for edge in 0 ..< 8 {
            next := (edge + 1) % 8
            quad(
                &result,
                rings[station][edge],
                rings[station + 1][edge],
                rings[station + 1][next],
                rings[station][next],
                .Body,
            )
        }
    }
    // Close the tapered nose and tail.
    nose_center := [3]f32{0, .48, -plan.length * .5}
    tail_center := [3]f32{0, .48, plan.length * .5}
    for edge in 0 ..< 8 {
        next := (edge + 1) % 8
        triangle(&result, nose_center, rings[0][next], rings[0][edge], .Body)
        triangle(&result, tail_center, rings[STATIONS - 1][edge], rings[STATIONS - 1][next], .Body)
    }

    // The greenhouse is another station loft. Its side panels are generated
    // as glass, while the roof, pillars, and lower rail remain structural.
    CABIN_STATIONS :: 7
    CABIN_RING_POINTS :: 8
    cabin_t := [CABIN_STATIONS]f32{-.50, -.43, -.20, .05, .28, .44, .50}
    cabin: [CABIN_STATIONS][CABIN_RING_POINTS][3]f32
    cabin_bottom := plan.belt_height - .10
    for t, index in cabin_t {
        z := plan.cabin_offset + t * plan.cabin_length
        end_taper := 1 - clamp((abs(t) - .28) / .22, f32(0), f32(1)) * .22
        if plan.kind == .Coupe && t > 0 {
            end_taper *= 1 - clamp(t / .50, f32(0), f32(1)) * .16
        }
        lower_half := plan.width * .42 * end_taper
        roof_half := plan.width * .325 * end_taper
        end_drop := clamp((abs(t) - .25) / .25, f32(0), f32(1)) * plan.cabin_height * .34
        if plan.kind == .Coupe && t > 0 {
            end_drop += clamp((t + .08) / .58, f32(0), f32(1)) * plan.cabin_height * .34
        }
        roof_y := plan.belt_height + plan.cabin_height - end_drop
        cabin[index] = {
            {-lower_half, cabin_bottom, z},
            {-lower_half, plan.belt_height, z},
            {-roof_half, roof_y - plan.cabin_height * .09, z},
            {-roof_half * .56, roof_y, z},
            {roof_half * .56, roof_y, z},
            {roof_half, roof_y - plan.cabin_height * .09, z},
            {lower_half, plan.belt_height, z},
            {lower_half, cabin_bottom, z},
        }
    }
    for station in 0 ..< CABIN_STATIONS - 1 {
        for edge in 0 ..< CABIN_RING_POINTS - 1 {
            // Side panes occupy the sloped shoulder faces. The narrow middle
            // station becomes a real B-pillar in topology, not an overlaid bar.
            part := Part.Body
            glass_segment := station != 2
            if plan.kind == .Coupe do glass_segment = true
            if plan.kind == .Delivery do glass_segment = station <= 1
            if (edge == 1 || edge == 5) && glass_segment do part = .Glass
            quad(
                &result,
                cabin[station][edge],
                cabin[station + 1][edge],
                cabin[station + 1][edge + 1],
                cabin[station][edge + 1],
                part,
            )
        }
    }
    // Front and rear glazing are each split down the centre in period fashion.
    front := 0
    back := CABIN_STATIONS - 1
    triangle(&result, cabin[front][0], cabin[front][1], cabin[front][2], .Body)
    quad(&result, cabin[front][1], cabin[front][2], cabin[front][5], cabin[front][6], .Glass)
    quad(&result, cabin[front][2], cabin[front][3], cabin[front][4], cabin[front][5], .Glass)
    triangle(&result, cabin[front][6], cabin[front][7], cabin[front][5], .Body)
    triangle(&result, cabin[back][0], cabin[back][2], cabin[back][1], .Body)
    back_part := plan.kind == .Delivery ? Part.Body : Part.Glass
    quad(&result, cabin[back][1], cabin[back][6], cabin[back][5], cabin[back][2], back_part)
    quad(&result, cabin[back][2], cabin[back][5], cabin[back][4], cabin[back][3], back_part)
    triangle(&result, cabin[back][6], cabin[back][5], cabin[back][7], .Body)
    if plan.kind == .Delivery {
        // Twin compact panes sit proud of the otherwise solid rear door skin.
        // The body cap remains closed behind them, avoiding one enormous
        // passenger-car window across the cargo opening.
        rear_z := plan.cabin_offset + plan.cabin_length * .502
        inner_x := plan.width * .035
        outer_x := plan.width * .245
        lower_y := plan.belt_height + plan.cabin_height * .18
        upper_y := plan.belt_height + plan.cabin_height * .54
        quad(
            &result,
            {-outer_x, lower_y, rear_z}, {-inner_x, lower_y, rear_z},
            {-inner_x, upper_y, rear_z}, {-outer_x, upper_y, rear_z},
            .Glass,
        )
        quad(
            &result,
            {inner_x, lower_y, rear_z}, {outer_x, lower_y, rear_z},
            {outer_x, upper_y, rear_z}, {inner_x, upper_y, rear_z},
            .Glass,
        )
    }

    // A narrow structural mullion makes the period split windscreen explicit
    // topology rather than relying on a material line painted over one pane.
    box(
        &result,
        {0, plan.belt_height + plan.cabin_height * .37, plan.cabin_offset - plan.cabin_length * .505},
        {.035, plan.cabin_height * .58, .035},
        .Trim,
    )

    if plan.kind == .Pickup {
        // A shallow coachbuilt tray grows from the same indexed mesh.  Its
        // floor, bulkhead, rails, and tailgate are separate closed regions,
        // allowing a readable open load bed rather than a sedan-like rear deck.
        bed_front := plan.cabin_offset + plan.cabin_length * .48
        bed_rear := plan.length * .47
        bed_length := bed_rear - bed_front
        bed_center := (bed_front + bed_rear) * .5
        rail_x := plan.width * .43
        box(&result, {0, .64, bed_center}, {plan.width * .72, .07, bed_length}, .Trim)
        box(&result, {-rail_x, .80, bed_center}, {.08, .34, bed_length}, .Body)
        box(&result, { rail_x, .80, bed_center}, {.08, .34, bed_length}, .Body)
        box(&result, {0, .80, bed_rear}, {plan.width * .90, .34, .08}, .Body)
    }
    if plan.kind == .Delivery {
        // Shallow pressed ribs stiffen the tall cargo quarters.  They share the
        // body material and read through light rather than painted decoration.
        cargo_front := plan.cabin_offset + plan.cabin_length * .08
        cargo_rear := plan.cabin_offset + plan.cabin_length * .43
        cargo_length := cargo_rear - cargo_front
        cargo_center := (cargo_front + cargo_rear) * .5
        panel_sides := [2]f32{-1, 1}
        panel_posts := [3]f32 {
            cargo_front,
            cargo_center,
            cargo_rear,
        }
        panel_rails := [2]f32 {
            plan.belt_height + plan.cabin_height * .10,
            plan.belt_height + plan.cabin_height * .64,
        }
        for side in panel_sides {
            x := side * plan.width * .408
            for z in panel_posts {
                box(
                    &result,
                    {x, plan.belt_height + plan.cabin_height * .37, z},
                    {.045, plan.cabin_height * .52, .055},
                    .Body,
                )
            }
            for y in panel_rails {
                box(&result, {x, y, cargo_center}, {.045, .055, cargo_length}, .Body)
            }
        }
        // The rear cargo doors are visibly split, matching the front period
        // windscreen without pretending the whole rear face is one hatch.
        box(
            &result,
            {0, plan.belt_height + plan.cabin_height * .34, plan.cabin_offset + plan.cabin_length * .505},
            {.035, plan.cabin_height * .64, .035},
            .Trim,
        )
    }
    if plan.kind == .Woody {
        // Structural ash framing follows both rear quarter windows.  Closed
        // indexed rails and posts give the material honest seams and a shallow
        // proud profile instead of floating decorative bars in the lab.
        frame_front := plan.cabin_offset + plan.cabin_length * .08
        frame_rear := plan.cabin_offset + plan.cabin_length * .46
        frame_length := frame_rear - frame_front
        frame_center := (frame_front + frame_rear) * .5
        frame_sides := [2]f32{-1, 1}
        frame_posts := [3]f32{frame_front, frame_center, frame_rear}
        for side in frame_sides {
            x := side * plan.width * .405
            box(&result, {x, plan.belt_height + .02, frame_center}, {.055, .075, frame_length}, .Timber)
            box(
                &result,
                {x, plan.belt_height + plan.cabin_height * .62, frame_center},
                {.055, .075, frame_length},
                .Timber,
            )
            for z in frame_posts {
                box(
                    &result,
                    {x, plan.belt_height + plan.cabin_height * .32, z},
                    {.055, plan.cabin_height * .58, .065},
                    .Timber,
                )
            }
        }
    }
    // Wheels are generated topology, not lab decoration.  Their shared rings
    // keep each tire compact while separate face discs preserve crisp period
    // whitewall and hub material boundaries.
    wheel_sides := [2]f32{-1, 1}
    wheel_axles := [2]f32{-plan.wheelbase * .5, plan.wheelbase * .5}
    for side in wheel_sides {
        for axle in wheel_axles {
            wheel(
                &result,
                side * plan.width * .525,
                plan.wheel_radius,
                axle,
                plan.wheel_width * .5,
                plan.wheel_radius,
                side,
            )
        }
    }
    return result
}
