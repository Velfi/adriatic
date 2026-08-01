package roads

import hs "../hs"
import "core:math"
import "core:mem"
import "core:testing"

tile_portable_config :: proc() -> hs.Portable_Config {
    config := hs.portable_default_config()
    config.exclusion_tag = "hs"
    config.exact_schema = true
    config.limits.max_payload = ROAD_TILE_RECORD_MAX_BYTES
    return config
}

tile_scalar_finite :: #force_inline proc(value: f32) -> bool {
    return value == value && !math.is_inf_f32(value)
}

tile_vec3_finite :: #force_inline proc(value: Vec3) -> bool {
    return tile_scalar_finite(value.x) && tile_scalar_finite(value.y) && tile_scalar_finite(value.z)
}

tile_valid :: proc(tile: ^Tile) -> bool {
    if tile == nil do return false
    node_ids := make(map[Node_Id]bool, context.temp_allocator)
    for node in tile.nodes {
        if u64(node.id) == 0 || !tile_vec3_finite(node.position) || !tile_vec3_finite(node.up) ||
           !tile_scalar_finite(node.junction_radius) || node.junction_radius < 0 {
            return false
        }
        if node_ids[node.id] do return false
        node_ids[node.id] = true
        if tile_key_at(node.position.x, node.position.z) != node.owner do return false
    }
    span_ids := make(map[[2]u64]bool, context.temp_allocator)
    for span in tile.spans {
        if u64(span.route_id) == 0 ||
           !tile_vec3_finite(span.curve.p0) || !tile_vec3_finite(span.curve.p1) ||
           !tile_vec3_finite(span.curve.p2) || !tile_vec3_finite(span.curve.p3) ||
           !tile_scalar_finite(span.half_width) || span.half_width <= 0 ||
           !tile_scalar_finite(span.shoulder_width) || span.shoulder_width < 0 ||
           !tile_scalar_finite(span.use_intensity) || span.use_intensity < 0 || span.use_intensity > 1 {
            return false
        }
        midpoint := spline_point(span.curve, .5)
        if tile_key_at(midpoint.x, midpoint.z) != tile.key do return false
        identity := [2]u64{u64(span.route_id), u64(span.span_index)}
        if span_ids[identity] do return false
        span_ids[identity] = true
    }
    return true
}

tile_encode :: proc(
    tile: ^Tile,
    alloc := context.allocator,
) -> (data: []byte, error: hs.Portable_Error, ok: bool) {
    if alloc.procedure == nil || !tile_valid(tile) {
        return nil, {kind = .Invalid_Argument, message = "road tile is invalid"}, false
    }
    return hs.portable_encode(
        any{data = rawptr(tile), id = typeid_of(Tile)},
        tile_portable_config(),
        alloc,
    )
}

tile_decode :: proc(
    data: []byte,
    alloc := context.allocator,
) -> (tile: ^Tile, error: hs.Portable_Error, ok: bool) {
    if alloc.procedure == nil || len(data) == 0 || len(data) > ROAD_TILE_RECORD_MAX_BYTES {
        return nil, {kind = .Invalid_Argument, message = "road tile payload is invalid"}, false
    }
    tile = new(Tile, alloc)
    if tile == nil do return nil, {kind = .Limit_Exceeded, message = "road tile allocation failed"}, false
    portable_error, decoded := hs.portable_decode(
        any{data = rawptr(tile), id = typeid_of(Tile)},
        data,
        tile_portable_config(),
        alloc,
    )
    if !decoded {
        tile_destroy(tile, alloc)
        return nil, portable_error, false
    }
    if !tile_valid(tile) {
        tile_destroy(tile, alloc)
        return nil, {kind = .Invalid_Metadata, message = "decoded road tile is invalid"}, false
    }
    return tile, {}, true
}

when ODIN_TEST {
    @(test)
    tile_codec_round_trip_is_deterministic :: proc(t: ^testing.T) {
        network: Network
        network_init(&network)
        defer network_destroy(&network)
        _, added := network_add_spline(
            &network,
            {{0, 0, 0}, {40, 0, 10}, {180, 0, -10}, {220, 0, 0}},
            7,
            1.5,
            .Cobblestone,
        )
        testing.expect(t, added)
        tile := network.loaded[Tile_Key{0, 0}]
        first, first_error, first_ok := tile_encode(tile)
        defer hs.portable_error_dispose(&first_error)
        testing.expect(t, first_ok)
        if !first_ok do return
        defer delete(first)
        second, second_error, second_ok := tile_encode(tile)
        defer hs.portable_error_dispose(&second_error)
        testing.expect(t, second_ok)
        if !second_ok do return
        defer delete(second)
        testing.expect(t, len(first) == len(second))
        for value, index in first do testing.expect_value(t, second[index], value)
        decoded, decode_error, decoded_ok := tile_decode(first)
        defer hs.portable_error_dispose(&decode_error)
        testing.expect(t, decoded_ok)
        if decoded_ok {
            defer tile_destroy(decoded)
            testing.expect_value(t, decoded.key, tile.key)
            testing.expect_value(t, len(decoded.spans), len(tile.spans))
        }
    }
}
