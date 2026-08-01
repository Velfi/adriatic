// Package flower_mesh generates small, renderer-independent flower meshes.
//
// A flower is built as a set of repeated petal surfaces around a domed
// receptacle.  Both whorled flowers (most core eudicots and monocots) and
// spiral flowers are supported.
package flower_mesh

import "core:math"

Petal_Shape :: enum u8 {
    Rounded,
    Pointed,
    Notched,
    Strap,
    Ovate,
    Spatulate,
    Lanceolate,
}

Arrangement :: enum u8 {
    Whorled,
    Spiral,
}

Cluster_Form :: enum u8 {
    Single,
    Dome,
    Ball,
}

Lifecycle_Stage :: enum u8 {
    Bud,
    Opening,
    Half_Open,
    Bloom,
    Fruit_Set,
    Immature_Fruit,
    Ripening_Fruit,
    Ripe_Fruit,
}

Fruit_Shape :: enum u8 {
    Berry,
    Drupe,
    Citrus,
    Pome,
}

Config :: struct {
    petal_shape:       Petal_Shape,
    arrangement:       Arrangement,
    petal_count:       int,
    whorl_count:       int,
    segments:          int,
    center_segments:   int,
    petal_length:      f32,
    petal_width:       f32,
    base_radius:       f32,
    center_radius:     f32,
    center_height:     f32,
    opening_angle:     f32,
    curl:              f32,
    cup:               f32,
    overlap:           f32,
    inner_whorl_scale: f32,
}

Fruit_Config :: struct {
    shape:       Fruit_Shape,
    segments:    int,
    rings:       int,
    radius:      f32,
    length:      f32,
    ridges:      int,
    ridge_depth: f32,
    tip:         f32,
}

Lifecycle_Config :: struct {
    stage:  Lifecycle_Stage,
    flower: Config,
    fruit:  Fruit_Config,
}

Cluster_Config :: struct {
    form:            Cluster_Form,
    flower_count:    int,
    radius:          f32,
    height:          f32,
    floret_scale:    f32,
    scale_variation: f32,
    phase:           f32,
}

Cluster_Instance :: struct {
    position: [3]f32,
    normal:   [3]f32,
    rotation: f32,
    scale:    f32,
}

Vertex :: struct {
    position: [3]f32,
    normal:   [3]f32,
    uv:       [2]f32,
}

MAX_PETALS :: 24
MAX_WHORLS :: 2
MAX_SEGMENTS :: 24
MAX_CENTER_SEGMENTS :: 32
// Dense mopheads routinely need more surface samples than a simple umbel.
// Keep this fixed-capacity and allocation-free, but leave enough headroom for
// small overlapping florets rather than forcing consumers to inflate them.
MAX_CLUSTER_FLOWERS :: 96
MAX_VERTICES :: MAX_PETALS * MAX_WHORLS * (MAX_SEGMENTS + 1) * 3 + MAX_CENTER_SEGMENTS + 1
MAX_INDICES :: MAX_PETALS * MAX_WHORLS * MAX_SEGMENTS * 12 + MAX_CENTER_SEGMENTS * 3

Mesh :: struct {
    vertices:     [MAX_VERTICES]Vertex,
    vertex_count: int,
    indices:      [MAX_INDICES]u16,
    index_count:  int,
}

Cluster :: struct {
    instances: [MAX_CLUSTER_FLOWERS]Cluster_Instance,
    count:     int,
}

defaults :: proc() -> Config {
    return {
        petal_shape = .Rounded,
        arrangement = .Whorled,
        petal_count = 5,
        whorl_count = 1,
        segments = 10,
        center_segments = 16,
        petal_length = 1,
        petal_width = .62,
        base_radius = .13,
        center_radius = .24,
        center_height = .12,
        opening_angle = .20,
        curl = .10,
        cup = .05,
        overlap = .08,
        inner_whorl_scale = .78,
    }
}

fruit_defaults :: proc(shape: Fruit_Shape = .Berry) -> Fruit_Config {
    result := Fruit_Config {
        shape       = shape,
        segments    = 16,
        rings       = 10,
        radius      = .42,
        length      = .82,
        ridges      = 0,
        ridge_depth = 0,
        tip         = .04,
    }
    switch shape {
    case .Berry:
    case .Drupe:
        result.radius = .36
        result.length = .92
        result.tip = .10
    case .Citrus:
        result.radius = .44
        result.length = 1.02
        result.ridges = 10
        result.ridge_depth = .025
        result.tip = .08
    case .Pome:
        result.radius = .47
        result.length = .82
        result.ridges = 5
        result.ridge_depth = .045
        result.tip = -.04
    }
    return result
}

cluster_defaults :: proc(form: Cluster_Form = .Dome) -> Cluster_Config {
    result := Cluster_Config {
        form            = form,
        flower_count    = 19,
        radius          = 1,
        height          = .52,
        floret_scale    = .18,
        scale_variation = .12,
        phase           = 0,
    }
    switch form {
    case .Single:
        result.flower_count = 1
        result.radius = 0
        result.height = 0
        result.floret_scale = 1
        result.scale_variation = 0
    case .Dome:
    case .Ball:
        result.flower_count = 24
        result.height = 1
        result.floret_scale = .16
    }
    return result
}

generate_cluster :: proc(config: Cluster_Config) -> Cluster {
    result: Cluster
    if int(config.form) < 0 || int(config.form) > int(Cluster_Form.Ball) do return result
    result.count = clamp(config.flower_count, 1, MAX_CLUSTER_FLOWERS)
    radius := max(config.radius, f32(0))
    height := max(config.height, f32(0))
    base_scale := max(config.floret_scale, f32(.01))
    variation := clamp(config.scale_variation, f32(0), f32(.8))
    golden_angle := f32(math.PI * (3 - math.sqrt(f32(5))))
    tau := f32(2 * math.PI)

    if config.form == .Single {
        result.instances[0] = {normal = {0, 0, 1}, scale = base_scale}
        result.count = 1
        return result
    }

    for index in 0 ..< result.count {
        angle := config.phase + f32(index) * golden_angle
        scale_wave := math.sin(angle * 1.71 + f32(index) * .83)
        instance_scale := base_scale * (1 + variation * scale_wave)
        if config.form == .Dome {
            if index == 0 {
                result.instances[index] = {
                    position = {0, 0, height},
                    normal = {0, 0, 1},
                    rotation = angle - math.floor(angle / tau) * tau,
                    scale = instance_scale,
                }
                continue
            }
            t := f32(index) / f32(max(result.count - 1, 1))
            ring := radius * math.sqrt(t)
            normalized_ring := radius > 1e-6 ? clamp(ring / radius, f32(0), f32(1)) : f32(0)
            z := height * math.sqrt(max(1 - normalized_ring * normalized_ring, f32(0)))
            normal := normalize3({math.cos(angle) * normalized_ring, math.sin(angle) * normalized_ring, max(z / max(height, f32(.001)), f32(.12))})
            result.instances[index] = {
                position = {math.cos(angle) * ring, math.sin(angle) * ring, z},
                normal = normal,
                rotation = angle - math.floor(angle / tau) * tau,
                scale = instance_scale,
            }
        } else {
            t := (f32(index) + .5) / f32(result.count)
            z_unit := 1 - 2 * t
            ring_unit := math.sqrt(max(1 - z_unit * z_unit, f32(0)))
            sphere_normal := [3]f32{math.cos(angle) * ring_unit, math.sin(angle) * ring_unit, z_unit}
            // Positions lie on an ellipsoid, whose gradient—not the radial
            // vector—is perpendicular to the surface. This distinction is
            // visible on oblate mopheads: the upper florets should turn
            // upward sooner than they would on a sphere.
            surface_normal := normalize3(
                {
                    radius > 1e-6 ? sphere_normal[0] / radius : sphere_normal[0],
                    radius > 1e-6 ? sphere_normal[1] / radius : sphere_normal[1],
                    height > 1e-6 ? sphere_normal[2] / height : sphere_normal[2],
                },
            )
            result.instances[index] = {
                position = {sphere_normal[0] * radius, sphere_normal[1] * radius, sphere_normal[2] * height},
                normal = surface_normal,
                rotation = angle - math.floor(angle / tau) * tau,
                scale = instance_scale,
            }
        }
    }
    return result
}

half_width :: proc(shape: Petal_Shape, t: f32) -> f32 {
    s := clamp(t, f32(0), f32(1))
    switch shape {
    case .Rounded:
        // Narrow claw, broad blade, and a soft rounded apex.
        return math.pow(max(math.sin(math.PI * s), f32(0)), f32(.58)) * (.72 + .28 * s)
    case .Pointed:
        return math.pow(max(math.sin(math.PI * s), f32(0)), f32(.52)) * math.pow(1 - s, f32(.22))
    case .Notched:
        envelope := math.pow(max(math.sin(math.PI * s), f32(0)), f32(.58)) * (.72 + .28 * s)
        notch := .42 * math.exp(-math.pow((s - .97) / .045, f32(2)))
        return max(envelope * (1 - notch), f32(0))
    case .Strap:
        base := min(s / .12, f32(1))
        tip := min((1 - s) / .10, f32(1))
        return math.pow(max(base * tip, f32(0)), f32(.35))
    case .Ovate:
        // An egg-shaped blade: widest beyond the midpoint, then tapering
        // smoothly to a small rounded apex.
        base := math.pow(max(s, f32(0)), f32(.52))
        tip := math.pow(max(1 - s, f32(0)), f32(.34))
        return base * tip * 1.75
    case .Spatulate:
        // A long narrow claw opening into a spoon-shaped distal blade.
        claw := min(s / .18, f32(1)) * (.18 + .82 * math.smoothstep(f32(.30), f32(.72), s))
        tip := math.pow(max((1 - s) / .18, f32(0)), f32(.30))
        return min(claw, f32(1)) * min(tip, f32(1))
    case .Lanceolate:
        // Slender throughout, with the maximum width below the midpoint and
        // a long taper toward the point.
        base := math.pow(max(s, f32(0)), f32(.42))
        taper := math.pow(max(1 - s, f32(0)), f32(.72))
        return min(base * taper * 2.05, f32(1))
    }
    return 0
}

sub3 :: proc(a, b: [3]f32) -> [3]f32 {
    return {a[0] - b[0], a[1] - b[1], a[2] - b[2]}
}

cross3 :: proc(a, b: [3]f32) -> [3]f32 {
    return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}
}

normalize3 :: proc(value: [3]f32) -> [3]f32 {
    magnitude := math.sqrt(value[0] * value[0] + value[1] * value[1] + value[2] * value[2])
    if magnitude <= 1e-7 do return {0, 0, 1}
    return {value[0] / magnitude, value[1] / magnitude, value[2] / magnitude}
}

dot3 :: proc(a, b: [3]f32) -> f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

petal_position :: proc(
    config: Config,
    angle, length, width, root_radius: f32,
    row, segments: int,
    side: f32,
) -> [3]f32 {
    t := f32(row) / f32(segments)
    profile := half_width(config.petal_shape, t)
    radial := root_radius + length * t * math.cos(config.opening_angle)
    lateral := side * width * .5 * profile
    // Curl raises the tip; cup raises both margins relative to the midrib.
    z :=
        length * t * math.sin(config.opening_angle) +
        config.curl * length * t * t +
        math.abs(side) * config.cup * width * profile
    cosine, sine := math.cos(angle), math.sin(angle)
    return {radial * cosine - lateral * sine, radial * sine + lateral * cosine, z}
}

generate :: proc(config: Config) -> Mesh {
    mesh: Mesh
    if int(config.petal_shape) < 0 || int(config.petal_shape) > int(Petal_Shape.Lanceolate) do return mesh
    petals := clamp(config.petal_count, 1, MAX_PETALS)
    whorls := clamp(config.whorl_count, 1, MAX_WHORLS)
    segments := clamp(config.segments, 3, MAX_SEGMENTS)
    center_segments := clamp(config.center_segments, 3, MAX_CENTER_SEGMENTS)
    length := max(config.petal_length, f32(.01))
    width := max(config.petal_width, f32(.01))
    tau := f32(2 * math.PI)
    golden_angle := f32(math.PI * (3 - math.sqrt(f32(5))))

    for whorl in 0 ..< whorls {
        scale := math.pow(clamp(config.inner_whorl_scale, f32(.1), f32(1)), f32(whorl))
        whorl_phase := config.arrangement == .Whorled ? f32(whorl) * math.PI / f32(petals) : f32(0)
        for petal in 0 ..< petals {
            organ_index := whorl * petals + petal
            angle := tau * f32(petal) / f32(petals) + whorl_phase
            if config.arrangement == .Spiral do angle = f32(organ_index) * golden_angle
            angle += clamp(config.overlap, f32(-1), f32(1)) * f32(whorl) / f32(max(whorls, 1))
            root_radius := max(config.base_radius, f32(0))
            if config.arrangement == .Spiral {
                root_radius += f32(organ_index) / f32(max(petals * whorls - 1, 1)) * config.center_radius * .35
            }
            first_vertex := mesh.vertex_count
            for row in 0 ..= segments {
                t := f32(row) / f32(segments)
                for column in 0 ..< 3 {
                    side := f32(column - 1)
                    position := petal_position(
                        config,
                        angle,
                        length * scale,
                        width * scale,
                        root_radius,
                        row,
                        segments,
                        side,
                    )
                    mesh.vertices[mesh.vertex_count] = {
                        position = position,
                        normal   = {0, 0, 1},
                        uv       = {f32(column) * .5, t},
                    }
                    mesh.vertex_count += 1
                }
            }
            for row in 0 ..< segments {
                a := u16(first_vertex + row * 3)
                b := u16(first_vertex + (row + 1) * 3)
                triangles := [12]u16{a, b, a + 1, a + 1, b, b + 1, a + 1, b + 1, a + 2, a + 2, b + 1, b + 2}
                for index in triangles {
                    mesh.indices[mesh.index_count] = index
                    mesh.index_count += 1
                }
            }
            // Smooth row normals from the local surface tangents.
            for row in 0 ..= segments {
                previous := max(row - 1, 0)
                next := min(row + 1, segments)
                across := sub3(
                    mesh.vertices[first_vertex + row * 3 + 2].position,
                    mesh.vertices[first_vertex + row * 3].position,
                )
                along := sub3(
                    mesh.vertices[first_vertex + next * 3 + 1].position,
                    mesh.vertices[first_vertex + previous * 3 + 1].position,
                )
                normal := normalize3(cross3(across, along))
                for column in 0 ..< 3 do mesh.vertices[first_vertex + row * 3 + column].normal = normal
            }
        }
    }

    // A shallow dome closes the corolla and can be shaded as a receptacle,
    // disk florets, or a pollen-bearing center by the renderer.
    center_first := mesh.vertex_count
    mesh.vertices[mesh.vertex_count] = {
        position = {0, 0, max(config.center_height, f32(0))},
        normal   = {0, 0, 1},
        uv       = {.5, .5},
    }
    mesh.vertex_count += 1
    center_radius := max(config.center_radius, f32(.01))
    for index in 0 ..< center_segments {
        angle := tau * f32(index) / f32(center_segments)
        mesh.vertices[mesh.vertex_count] = {
            position = {center_radius * math.cos(angle), center_radius * math.sin(angle), 0},
            normal   = normalize3(
                {math.cos(angle) * config.center_height, math.sin(angle) * config.center_height, center_radius},
            ),
            uv       = {.5 + .5 * math.cos(angle), .5 + .5 * math.sin(angle)},
        }
        mesh.vertex_count += 1
    }
    for index in 0 ..< center_segments {
        next := (index + 1) % center_segments
        mesh.indices[mesh.index_count + 0] = u16(center_first)
        mesh.indices[mesh.index_count + 1] = u16(center_first + 1 + index)
        mesh.indices[mesh.index_count + 2] = u16(center_first + 1 + next)
        mesh.index_count += 3
    }
    return mesh
}

fruit_position :: proc(config: Fruit_Config, longitude, latitude: f32) -> [3]f32 {
    cosine_latitude := max(math.cos(latitude), f32(0))
    axial := math.sin(latitude)
    envelope := cosine_latitude
    switch config.shape {
    case .Berry:
    case .Drupe:
        // A slightly narrower shoulder and pointed distal end.
        envelope *= .94 + .12 * (1 - axial) * .5
    case .Citrus:
        envelope = math.pow(cosine_latitude, f32(.88))
    case .Pome:
        // Broad shoulders with a narrowed blossom end.
        envelope = math.pow(cosine_latitude, f32(.72)) * (1.03 - .13 * axial)
    }
    ridge := f32(1)
    if config.ridges > 0 {
        ridge += clamp(config.ridge_depth, f32(0), f32(.2)) * math.cos(f32(config.ridges) * longitude)
    }
    radius := max(config.radius, f32(.01)) * envelope * ridge
    z := axial * max(config.length, f32(.01)) * .5
    if math.abs(axial) > .72 {
        end := (math.abs(axial) - .72) / .28
        z += config.tip * end * end * (axial >= 0 ? f32(1) : f32(-.35))
    }
    return {radius * math.cos(longitude), radius * math.sin(longitude), z}
}

generate_fruit :: proc(config: Fruit_Config) -> Mesh {
    mesh: Mesh
    if int(config.shape) < 0 || int(config.shape) > int(Fruit_Shape.Pome) do return mesh
    segments := clamp(config.segments, 6, MAX_CENTER_SEGMENTS)
    rings := clamp(config.rings, 4, MAX_SEGMENTS)
    tau := f32(2 * math.PI)
    columns := segments + 1

    for ring in 0 ..= rings {
        v := f32(ring) / f32(rings)
        latitude := -f32(math.PI) * .5 + f32(math.PI) * v
        for segment in 0 ..= segments {
            u := f32(segment) / f32(segments)
            longitude := tau * u
            position := fruit_position(config, longitude, latitude)
            mesh.vertices[mesh.vertex_count] = {
                position = position,
                normal   = {0, 0, latitude < 0 ? f32(-1) : f32(1)},
                uv       = {u, v},
            }
            mesh.vertex_count += 1
        }
    }
    for ring in 0 ..< rings {
        for segment in 0 ..< segments {
            a := u16(ring * columns + segment)
            b := u16((ring + 1) * columns + segment)
            triangles := [6]u16{a, b, a + 1, a + 1, b, b + 1}
            for index in triangles {
                mesh.indices[mesh.index_count] = index
                mesh.index_count += 1
            }
        }
    }
    // Central differences produce smooth normals for every profile, including
    // ribbed fruit. Duplicate seam vertices intentionally share positions.
    for ring in 0 ..= rings {
        previous_ring := max(ring - 1, 0)
        next_ring := min(ring + 1, rings)
        for segment in 0 ..= segments {
            previous_segment := segment == 0 ? segments - 1 : segment - 1
            next_segment := segment == segments ? 1 : segment + 1
            index := ring * columns + segment
            around := sub3(
                mesh.vertices[ring * columns + next_segment].position,
                mesh.vertices[ring * columns + previous_segment].position,
            )
            along := sub3(
                mesh.vertices[next_ring * columns + segment].position,
                mesh.vertices[previous_ring * columns + segment].position,
            )
            normal := normalize3(cross3(around, along))
            if dot3(normal, mesh.vertices[index].position) < 0 {
                normal = {-normal[0], -normal[1], -normal[2]}
            }
            mesh.vertices[index].normal = normal
        }
    }
    return mesh
}

generate_lifecycle :: proc(config: Lifecycle_Config) -> Mesh {
    switch config.stage {
    case .Bud:
        flower := config.flower
        flower.petal_length *= .34
        flower.petal_width *= .48
        flower.opening_angle = 1.12
        flower.curl *= .25
        flower.cup *= .35
        flower.center_radius *= .72
        flower.center_height *= .72
        return generate(flower)
    case .Opening:
        flower := config.flower
        flower.petal_length *= .55
        flower.petal_width *= .68
        flower.opening_angle = .78
        flower.curl *= .40
        flower.cup *= .55
        flower.center_radius *= .80
        flower.center_height *= .80
        return generate(flower)
    case .Half_Open:
        flower := config.flower
        flower.petal_length *= .78
        flower.petal_width *= .86
        flower.opening_angle = .46
        flower.curl *= .65
        flower.cup *= .78
        flower.center_radius *= .90
        flower.center_height *= .90
        return generate(flower)
    case .Bloom:
        return generate(config.flower)
    case .Fruit_Set:
        fruit := config.fruit
        fruit.radius *= .46
        fruit.length *= .52
        fruit.tip *= .35
        fruit.ridge_depth *= .45
        return generate_fruit(fruit)
    case .Immature_Fruit:
        fruit := config.fruit
        fruit.radius *= .68
        fruit.length *= .72
        fruit.tip *= .55
        fruit.ridge_depth *= .70
        return generate_fruit(fruit)
    case .Ripening_Fruit:
        fruit := config.fruit
        fruit.radius *= .86
        fruit.length *= .90
        fruit.tip *= .80
        fruit.ridge_depth *= .90
        return generate_fruit(fruit)
    case .Ripe_Fruit:
        return generate_fruit(config.fruit)
    }
    return {}
}
