package roads

import "core:math"
import "core:testing"

ROAD_TILE_SIZE :: f32(256)
ROAD_STREAM_LOAD_RADIUS :: f32(1024)
ROAD_STREAM_EVICT_RADIUS :: f32(1280)
ROAD_TILE_RECORD_MAX_BYTES :: 16 * 1024 * 1024

Node_Id :: distinct u64
Route_Id :: distinct u64

Tile_Key :: struct {
    x, z: i32,
}

Query_Detail :: enum u8 {
    Missing,
    Pending,
    Proxy,
    Detailed,
}

Endpoint_Kind :: enum u8 {
    Junction,
    Portal,
}

Spline :: struct {
    p0, p1, p2, p3: Vec3,
}

Network_Node :: struct {
    id:              Node_Id,
    position:        Vec3,
    up:              Vec3,
    junction_radius: f32,
    kind:            Endpoint_Kind,
    owner:           Tile_Key,
}

Route_Span :: struct {
    route_id:       Route_Id,
    span_index:     u32,
    curve:          Spline,
    half_width:     f32,
    shoulder_width: f32,
    pavement:       Pavement,
    use_intensity:  f32,
    start_kind:     Endpoint_Kind,
    end_kind:       Endpoint_Kind,
}

Tile :: struct {
    key:      Tile_Key,
    revision: u64,
    nodes:    [dynamic]Network_Node,
    spans:    [dynamic]Route_Span,
    dirty:    bool `hs:"-" fixture:"-"`,
    pinned:   bool `hs:"-" fixture:"-"`,
}

Proxy_Route :: struct {
    id:           Route_Id,
    points:       [dynamic]Vec3,
    tiles:        [dynamic]Tile_Key,
    min_x, min_z: f32,
    max_x, max_z: f32,
    half_width:   f32,
    pavement:     Pavement,
}

Tile_Directory_Entry :: struct {
    key:          Tile_Key,
    offset:       u64,
    encoded_size: u64,
    checksum:     u64,
    revision:     u64,
}

Network_Metadata :: struct {
    tile_size:     f32,
    next_node_id:  u64,
    next_route_id: u64,
    proxy:         [dynamic]Proxy_Route,
    directory:     [dynamic]Tile_Directory_Entry,
}

Network :: struct {
    metadata: Network_Metadata,
    loaded:   map[Tile_Key]^Tile,
    pending:  map[Tile_Key]bool,
}

Nearest_Result :: struct {
    detail:           Query_Detail,
    route_id:         Route_Id,
    position:         Vec3,
    distance_squared: f32,
    pavement:         Pavement,
    found:            bool,
}

tile_key_at :: #force_inline proc(x, z: f32, tile_size := ROAD_TILE_SIZE) -> Tile_Key {
    size := max(tile_size, f32(.001))
    return {x = i32(math.floor(f64(x / size))), z = i32(math.floor(f64(z / size)))}
}

tile_minimum :: #force_inline proc(key: Tile_Key, tile_size := ROAD_TILE_SIZE) -> (x, z: f32) {
    return f32(key.x) * tile_size, f32(key.z) * tile_size
}

network_init :: proc(network: ^Network, allocator := context.allocator) {
    if network == nil do return
    network^ = {
        metadata = {
            tile_size = ROAD_TILE_SIZE,
            next_node_id = 1,
            next_route_id = 1,
            proxy = make([dynamic]Proxy_Route, allocator),
            directory = make([dynamic]Tile_Directory_Entry, allocator),
        },
        loaded = make(map[Tile_Key]^Tile, allocator),
        pending = make(map[Tile_Key]bool, allocator),
    }
}

tile_destroy :: proc(tile: ^Tile, allocator := context.allocator) {
    if tile == nil do return
    delete(tile.nodes)
    delete(tile.spans)
    free(tile, allocator)
}

network_destroy :: proc(network: ^Network, allocator := context.allocator) {
    if network == nil do return
    for _, tile in network.loaded do tile_destroy(tile, allocator)
    delete(network.loaded)
    delete(network.pending)
    for &route in network.metadata.proxy {
        delete(route.points)
        delete(route.tiles)
    }
    delete(network.metadata.proxy)
    delete(network.metadata.directory)
    network^ = {}
}

network_tile_get_or_create :: proc(network: ^Network, key: Tile_Key, allocator := context.allocator) -> ^Tile {
    if network == nil do return nil
    if network.loaded == nil do network_init(network, allocator)
    if tile, found := network.loaded[key]; found do return tile
    tile := new(Tile, allocator)
    if tile == nil do return nil
    tile.key = key
    tile.nodes = make([dynamic]Network_Node, allocator)
    tile.spans = make([dynamic]Route_Span, allocator)
    network.loaded[key] = tile
    return tile
}

spline_point :: #force_inline proc(curve: Spline, t: f32) -> Vec3 {
    amount := clamp(t, f32(0), f32(1))
    inverse := 1 - amount
    return(
        curve.p0 * (inverse * inverse * inverse) +
        curve.p1 * (3 * inverse * inverse * amount) +
        curve.p2 * (3 * inverse * amount * amount) +
        curve.p3 * (amount * amount * amount) \
    )
}

spline_split :: proc(curve: Spline, t: f32) -> (before, after: Spline) {
    amount := clamp(t, f32(0), f32(1))
    q0 := curve.p0 + (curve.p1 - curve.p0) * amount
    q1 := curve.p1 + (curve.p2 - curve.p1) * amount
    q2 := curve.p2 + (curve.p3 - curve.p2) * amount
    r0 := q0 + (q1 - q0) * amount
    r1 := q1 + (q2 - q1) * amount
    point := r0 + (r1 - r0) * amount
    return {curve.p0, q0, r0, point}, {point, r1, q2, curve.p3}
}

spline_hull_inside_tile :: proc(curve: Spline, key: Tile_Key, tile_size: f32) -> bool {
    minimum_x, minimum_z := tile_minimum(key, tile_size)
    maximum_x, maximum_z := minimum_x + tile_size, minimum_z + tile_size
    points := [4]Vec3{curve.p0, curve.p1, curve.p2, curve.p3}
    for point in points {
        if point.x < minimum_x || point.x > maximum_x || point.z < minimum_z || point.z > maximum_z {
            return false
        }
    }
    return true
}

spline_first_tile_exit_recursive :: proc(
    curve: Spline,
    origin: Tile_Key,
    tile_size: f32,
    depth: int,
) -> (
    t: f32,
    found: bool,
) {
    if spline_hull_inside_tile(curve, origin, tile_size) do return 1, false
    if depth <= 0 {
        previous_t := f32(0)
        for sample in 1 ..= 16 {
            sample_t := f32(sample) / 16
            if tile_key_at(spline_point(curve, sample_t).x, spline_point(curve, sample_t).z, tile_size) == origin {
                previous_t = sample_t
                continue
            }
            low, high := previous_t, sample_t
            for _ in 0 ..< 28 {
                middle := (low + high) * .5
                point := spline_point(curve, middle)
                if tile_key_at(point.x, point.z, tile_size) == origin {
                    low = middle
                } else {
                    high = middle
                }
            }
            // Choose the first parameter known to belong to the destination
            // tile so the remainder cannot repeatedly split on the same edge.
            return high, true
        }
        return 1, false
    }
    before, after := spline_split(curve, .5)
    if local, before_found := spline_first_tile_exit_recursive(before, origin, tile_size, depth - 1); before_found {
        return local * .5, true
    }
    if local, after_found := spline_first_tile_exit_recursive(after, origin, tile_size, depth - 1); after_found {
        return .5 + local * .5, true
    }
    return 1, false
}

spline_first_tile_exit :: proc(curve: Spline, tile_size: f32) -> (t: f32, found: bool) {
    forward := spline_point(curve, .0001)
    origin := tile_key_at(forward.x, forward.z, tile_size)
    amount, exited := spline_first_tile_exit_recursive(curve, origin, tile_size, 20)
    if !exited do return 1, false
    return clamp(amount, f32(.0000001), f32(.9999999)), true
}

network_append_span :: proc(network: ^Network, span: Route_Span, allocator := context.allocator) -> bool {
    midpoint := spline_point(span.curve, .5)
    key := tile_key_at(midpoint.x, midpoint.z, network.metadata.tile_size)
    tile := network_tile_get_or_create(network, key, allocator)
    if tile == nil do return false
    append(&tile.spans, span)
    tile.revision += 1
    tile.dirty = true
    return true
}

network_add_spline :: proc(
    network: ^Network,
    curve: Spline,
    width: f32,
    shoulder_width: f32 = 1,
    pavement: Pavement = .Asphalt,
    use_intensity: f32 = 1,
    allocator := context.allocator,
) -> (
    Route_Id,
    bool,
) {
    if network == nil ||
       width <= 0 ||
       width != width ||
       math.is_inf_f32(width) ||
       !tile_vec3_finite(curve.p0) ||
       !tile_vec3_finite(curve.p1) ||
       !tile_vec3_finite(curve.p2) ||
       !tile_vec3_finite(curve.p3) {
        return {}, false
    }
    if network.loaded == nil do network_init(network, allocator)
    route_id := Route_Id(network.metadata.next_route_id)
    Staged_Span :: struct {
        key:  Tile_Key,
        span: Route_Span,
    }
    staged := make([dynamic]Staged_Span, context.temp_allocator)
    proxy_points := make([dynamic]Vec3, allocator)
    proxy_tiles := make([dynamic]Tile_Key, allocator)
    staged_owned := true
    defer if staged_owned {
        delete(proxy_points)
        delete(proxy_tiles)
    }
    append(&proxy_points, curve.p0)
    pending := curve
    span_index: u32
    minimum_x := min(min(curve.p0.x, curve.p1.x), min(curve.p2.x, curve.p3.x))
    minimum_z := min(min(curve.p0.z, curve.p1.z), min(curve.p2.z, curve.p3.z))
    maximum_x := max(max(curve.p0.x, curve.p1.x), max(curve.p2.x, curve.p3.x))
    maximum_z := max(max(curve.p0.z, curve.p1.z), max(curve.p2.z, curve.p3.z))
    minimum_tile := tile_key_at(minimum_x, minimum_z, network.metadata.tile_size)
    maximum_tile := tile_key_at(maximum_x, maximum_z, network.metadata.tile_size)
    maximum_spans := max(1, (int(maximum_tile.x - minimum_tile.x) + int(maximum_tile.z - minimum_tile.z) + 4) * 4)
    complete := false
    for _ in 0 ..< maximum_spans {
        amount, split := spline_first_tile_exit(pending, network.metadata.tile_size)
        piece := pending
        if split {
            source_key := tile_key_at(pending.p0.x, pending.p0.z, network.metadata.tile_size)
            piece, pending = spline_split(pending, amount)
            destination_sample := spline_point(pending, .001)
            destination_key := tile_key_at(destination_sample.x, destination_sample.z, network.metadata.tile_size)
            portal := piece.p3
            if source_key.x != destination_key.x {
                portal.x = f32(max(source_key.x, destination_key.x)) * network.metadata.tile_size
            }
            if source_key.z != destination_key.z {
                portal.z = f32(max(source_key.z, destination_key.z)) * network.metadata.tile_size
            }
            piece.p3, pending.p0 = portal, portal
        }
        span := Route_Span {
            route_id       = route_id,
            span_index     = span_index,
            curve          = piece,
            half_width     = width * .5,
            shoulder_width = max(shoulder_width, f32(0)),
            pavement       = pavement,
            use_intensity  = clamp(use_intensity, f32(0), f32(1)),
            start_kind     = span_index == 0 ? .Junction : .Portal,
            end_kind       = split ? .Portal : .Junction,
        }
        midpoint := spline_point(piece, .5)
        key := tile_key_at(midpoint.x, midpoint.z, network.metadata.tile_size)
        append(&staged, Staged_Span{key, span})
        if len(proxy_tiles) == 0 || proxy_tiles[len(proxy_tiles) - 1] != key do append(&proxy_tiles, key)
        // The resident proxy is a lightweight centerline, not an endpoint
        // chord. Eight samples per ownership span keep distant selection and
        // routing close to the detailed cubic without retaining tile payloads.
        for proxy_sample in 1 ..= 8 {
            append(&proxy_points, spline_point(piece, f32(proxy_sample) / 8))
        }
        span_index += 1
        if !split {
            complete = true
            break
        }
    }
    if !complete do return {}, false

    target_tiles := make(map[Tile_Key]^Tile, context.temp_allocator)
    created_tiles := make([dynamic]Tile_Key, context.temp_allocator)
    for item in staged {
        if _, found := target_tiles[item.key]; found do continue
        _, existed := network.loaded[item.key]
        tile := network_tile_get_or_create(network, item.key, allocator)
        if tile == nil {
            for key in created_tiles {
                created := network.loaded[key]
                delete_key(&network.loaded, key)
                tile_destroy(created, allocator)
            }
            return {}, false
        }
        target_tiles[item.key] = tile
        if !existed do append(&created_tiles, item.key)
    }
    for item in staged {
        tile := target_tiles[item.key]
        append(&tile.spans, item.span)
        tile.revision += 1
        tile.dirty = true
    }
    append(&network.metadata.proxy, Proxy_Route {
        id         = route_id,
        points     = proxy_points,
        tiles      = proxy_tiles,
        min_x      = minimum_x,
        min_z      = minimum_z,
        max_x      = maximum_x,
        max_z      = maximum_z,
        half_width = width * .5,
        pavement   = pavement,
    })
    network.metadata.next_route_id += 1
    staged_owned = false
    return route_id, true
}

segment_nearest :: proc(a, b, point: Vec3) -> (position: Vec3, distance_squared: f32) {
    delta := b - a
    length_squared := delta.x * delta.x + delta.y * delta.y + delta.z * delta.z
    amount := f32(0)
    if length_squared > .000001 {
        offset := point - a
        amount = clamp((offset.x * delta.x + offset.y * delta.y + offset.z * delta.z) / length_squared, 0, 1)
    }
    position = a + delta * amount
    difference := point - position
    return position, difference.x * difference.x + difference.y * difference.y + difference.z * difference.z
}

network_nearest_proxy :: proc(network: ^Network, point: Vec3) -> Nearest_Result {
    result := Nearest_Result {
        detail           = .Missing,
        distance_squared = max(f32),
    }
    if network == nil do return result
    for route in network.metadata.proxy {
        if len(route.points) < 2 do continue
        for index in 0 ..< len(route.points) - 1 {
            position, distance_squared := segment_nearest(route.points[index], route.points[index + 1], point)
            if distance_squared >= result.distance_squared do continue
            result = {
                detail           = .Proxy,
                route_id         = route.id,
                position         = position,
                distance_squared = distance_squared,
                pavement         = route.pavement,
                found            = true,
            }
        }
    }
    return result
}

network_nearest :: proc(network: ^Network, point: Vec3, samples: int = 24) -> Nearest_Result {
    result := network_nearest_proxy(network, point)
    if network == nil || network.loaded == nil do return result
    radius := max(samples, 4)
    key := tile_key_at(point.x, point.z, network.metadata.tile_size)
    detailed := false
    for z in key.z - 1 ..= key.z + 1 {
        for x in key.x - 1 ..= key.x + 1 {
            tile, found := network.loaded[Tile_Key{x, z}]
            if !found do continue
            detailed = true
            for span in tile.spans {
                previous := span.curve.p0
                for sample in 1 ..= radius {
                    current := spline_point(span.curve, f32(sample) / f32(radius))
                    position, distance_squared := segment_nearest(previous, current, point)
                    if !result.found || distance_squared <= result.distance_squared {
                        result = {
                            detail           = .Detailed,
                            route_id         = span.route_id,
                            position         = position,
                            distance_squared = distance_squared,
                            pavement         = span.pavement,
                            found            = true,
                        }
                    }
                    previous = current
                }
            }
        }
    }
    if !detailed && network.pending[key] do result.detail = .Pending
    return result
}

when ODIN_TEST {
    @(test)
    network_tile_keys_are_world_aligned_across_zero :: proc(t: ^testing.T) {
        testing.expect_value(t, tile_key_at(0, 0), Tile_Key{0, 0})
        testing.expect_value(t, tile_key_at(255.999, 12), Tile_Key{0, 0})
        testing.expect_value(t, tile_key_at(256, 12), Tile_Key{1, 0})
        testing.expect_value(t, tile_key_at(-.001, 12), Tile_Key{-1, 0})
        testing.expect_value(t, tile_key_at(-256, -256), Tile_Key{-1, -1})
    }

    @(test)
    network_splits_long_curves_into_portal_spans_without_changing_shape :: proc(t: ^testing.T) {
        network: Network
        network_init(&network)
        defer network_destroy(&network)
        curve := Spline{{-300, 2, -40}, {-80, 7, 420}, {380, -3, -420}, {700, 4, 40}}
        route, added := network_add_spline(&network, curve, 8, 2, .Asphalt)
        testing.expect(t, added)
        testing.expect(t, u64(route) != 0)
        span_count := 0
        last_index: u32
        for _, tile in network.loaded {
            for span in tile.spans {
                testing.expect_value(t, span.route_id, route)
                if span.span_index > 0 do testing.expect_value(t, span.start_kind, Endpoint_Kind.Portal)
                last_index = max(last_index, span.span_index)
                span_count += 1
            }
        }
        testing.expect(t, span_count > 3)
        testing.expect_value(t, len(network.metadata.proxy), 1)
        testing.expect_value(t, network.metadata.proxy[0].points[0], curve.p0)
        testing.expect_value(t, network.metadata.proxy[0].points[len(network.metadata.proxy[0].points) - 1], curve.p3)
        testing.expect(t, last_index > 1)
    }

    @(test)
    network_queries_proxy_then_loaded_detail :: proc(t: ^testing.T) {
        network: Network
        network_init(&network)
        defer network_destroy(&network)
        _, added := network_add_spline(
            &network,
            {{0, 0, 0}, {80, 0, 0}, {180, 0, 0}, {300, 0, 0}},
            6,
            pavement = .Gravel,
        )
        testing.expect(t, added)
        proxy := network_nearest_proxy(&network, {120, 0, 10})
        testing.expect(t, proxy.found)
        testing.expect_value(t, proxy.detail, Query_Detail.Proxy)
        detailed := network_nearest(&network, {120, 0, 10})
        testing.expect(t, detailed.found)
        testing.expect_value(t, detailed.detail, Query_Detail.Detailed)
        testing.expect_value(t, detailed.pavement, Pavement.Gravel)
    }

    @(test)
    network_detects_brief_tile_excursions_and_proxy_follows_curve :: proc(t: ^testing.T) {
        network: Network
        network_init(&network)
        defer network_destroy(&network)
        curve := Spline{{10, 0, 10}, {10, 0, 700}, {30, 0, -700}, {40, 0, 10}}
        _, added := network_add_spline(&network, curve, 5)
        testing.expect(t, added)
        testing.expect(t, len(network.metadata.proxy) == 1)
        if len(network.metadata.proxy) != 1 do return
        proxy := &network.metadata.proxy[0]
        testing.expect(t, len(proxy.tiles) > 1)
        testing.expect(t, len(proxy.points) > 2)
        query_point := spline_point(curve, .22)
        nearest := network_nearest_proxy(&network, query_point)
        testing.expect(t, nearest.found)
        testing.expect(t, nearest.distance_squared < 64)
    }
}
