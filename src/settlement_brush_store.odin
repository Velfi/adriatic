package main

import "core:mem"
import "core:os"

SETTLEMENT_BRUSH_STORE_PATH :: "adriatic.settlements"
SETTLEMENT_BRUSH_STORE_MAGIC :: [8]u8{'A', 'D', 'R', 'S', 'E', 'T', 'T', '1'}
SETTLEMENT_BRUSH_STORE_VERSION :: u32(1)

Settlement_Brush_Store :: struct {
    magic:             [8]u8,
    version:           u32,
    count:             u32,
    next_component_id: u32,
    pieces:            [SETTLEMENT_BRUSH_PIECE_CAPACITY]Settlement_Brush_Piece,
    checksum:          u64,
}

settlement_brush_store_checksum :: proc(store: ^Settlement_Brush_Store) -> u64 {
    if store == nil do return 0
    bytes := mem.slice_ptr(
        cast([^]u8)&store.version,
        int(offset_of(Settlement_Brush_Store, checksum) - offset_of(Settlement_Brush_Store, version)),
    )
    hash: u64 = 14695981039346656037
    for byte in bytes do hash = (hash ~ u64(byte)) * 1099511628211
    return hash
}

settlement_brush_store_save :: proc(plan: ^Settlement_Plan, path: string = SETTLEMENT_BRUSH_STORE_PATH) -> bool {
    if plan == nil ||
       path == "" ||
       plan.brush_piece_count < 0 ||
       plan.brush_piece_count > SETTLEMENT_BRUSH_PIECE_CAPACITY {
        return false
    }
    store := Settlement_Brush_Store {
        magic             = SETTLEMENT_BRUSH_STORE_MAGIC,
        version           = SETTLEMENT_BRUSH_STORE_VERSION,
        count             = u32(plan.brush_piece_count),
        next_component_id = plan.next_brush_component_id,
        pieces            = plan.brush_pieces,
    }
    store.checksum = settlement_brush_store_checksum(&store)
    bytes := mem.slice_ptr(cast([^]u8)&store, size_of(store))
    return os.write_entire_file(path, bytes) == nil
}

settlement_brush_store_load :: proc(plan: ^Settlement_Plan, path: string = SETTLEMENT_BRUSH_STORE_PATH) -> bool {
    if plan == nil || path == "" do return false
    bytes, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil || len(bytes) != size_of(Settlement_Brush_Store) do return false
    store := cast(^Settlement_Brush_Store)raw_data(bytes)
    if store.magic != SETTLEMENT_BRUSH_STORE_MAGIC ||
       store.version != SETTLEMENT_BRUSH_STORE_VERSION ||
       store.count > SETTLEMENT_BRUSH_PIECE_CAPACITY ||
       store.checksum != settlement_brush_store_checksum(store) {
        return false
    }
    plan.brush_pieces = store.pieces
    plan.brush_piece_count = int(store.count)
    plan.next_brush_component_id = store.next_component_id
    return true
}
