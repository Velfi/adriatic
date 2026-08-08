package farmland

import "core:math"
import "core:sync"
import markov "zelda_engine:markov"

GRID_WIDTH :: 25
GRID_HEIGHT :: 19
MIN_GRID_SPAN :: 6
MAX_GRID_SPAN :: 64
CELL_METERS :: f32(5)
PARCEL_CAPACITY :: 24
// A 5 m cell covers 25 m², so 300 cells are .75 ha. This is deliberately
// smaller than modern English field averages (especially arable fields), but
// still keeps these compact game-scale farm envelopes from becoming mazes.
TARGET_PARCEL_CELLS :: 300

Crop :: enum u8 {
    Wheat,
    Olive,
    Vineyard,
    Fallow,
    Clover,
}

Tradition :: enum u8 {
    Ancient_Enclosure,
    Parliamentary_Enclosure,
}

Parcel :: struct {
    min_x, min_z: int,
    max_x, max_z: int,
    crop:         Crop,
    row_axis_x:   bool,
    phase:        f32,
    tint:         f32,
}

Plan :: struct {
    seed:         u32,
    width:        int,
    height:       int,
    tradition:    Tradition,
    parcels:      [PARCEL_CAPACITY]Parcel,
    parcel_count: int,
    garden_x:     int,
    garden_z:     int,
    garden_span:  int,
    valid:        bool,
}

markov_generation_lock: sync.Mutex

mix :: proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * u32(0x7feb352d)
    result = (result ~ (result >> 15)) * u32(0x846ca68b)
    return result ~ (result >> 16)
}

variation_model :: proc() -> markov.Proc_Node {
    empty, grown, accent := 0, 1, 2
    return markov.sequence(
        markov.kattr(.values, markov.values_count(3)),
        markov.kattr(.origin, true),
        markov.one(
            markov.kattr(
                .in_,
                markov.match_layer(
                    markov.match_row(markov.one_of(markov.sym(grown)), markov.one_of(markov.sym(empty))),
                ),
            ),
            markov.kattr(.out, markov.write_layer(markov.write_row(markov.keep(), markov.sym(grown)))),
            markov.kattr(.steps, 34),
        ),
        markov.one(
            markov.kattr(.in_, markov.match_layer(markov.match_row(markov.one_of(markov.sym(grown))))),
            markov.kattr(.out, markov.write_layer(markov.write_row(markov.sym(accent)))),
            markov.kattr(.steps, 12),
        ),
    )
}

variation_at :: proc(state: []u8, x, z: int, seed: u32) -> f32 {
    if len(state) == 49 {
        value := state[(abs(z) % 7) * 7 + abs(x) % 7]
        if value == 2 do return .92
        if value == 1 do return .64
    }
    return f32(mix(seed ~ u32(x * 73856093) ~ u32(z * 19349663)) & 255) / 255
}

append_parcel :: proc(plan: ^Plan, parcel: Parcel) {
    if plan.parcel_count >= len(plan.parcels) do return
    plan.parcels[plan.parcel_count] = parcel
    plan.parcel_count += 1
}

generate_sized_for_tradition :: proc(
    seed: u32,
    requested_width, requested_height: int,
    tradition: Tradition,
    allocator := context.temp_allocator,
) -> Plan {
    previous_allocator := context.allocator
    context.allocator = allocator
    defer context.allocator = previous_allocator

    // Keep the Markov result in value-owned storage before releasing the
    // generation lock. Frames use the caller's temporary allocator, which can
    // be reused by other generators running on test worker threads.
    state_storage: [49]u8
    state_count := 0
    {
        sync.mutex_lock(&markov_generation_lock)
        defer sync.mutex_unlock(&markov_generation_lock)
        model := variation_model()
        ip, loaded := markov.load_model_proc(model, {7, 7, 1})
        if loaded {
            frames := markov.run(ip, int(seed), 0, false, allocator)
            if len(frames) > 0 {
                generated := frames[len(frames) - 1].state
                state_count = min(len(generated), len(state_storage))
                copy(state_storage[:state_count], generated[:state_count])
            }
            markov.frames_destroy(&frames, allocator)
            defer markov.interpreter_destroy(ip)
        }
    }
    state := state_storage[:state_count]

    plan: Plan
    plan.seed = seed
    plan.width = clamp(requested_width, MIN_GRID_SPAN, MAX_GRID_SPAN)
    plan.height = clamp(requested_height, MIN_GRID_SPAN, MAX_GRID_SPAN)
    plan.tradition = tradition
    append_parcel(&plan, {min_x = 0, min_z = 0, max_x = plan.width, max_z = plan.height})

    // Repeatedly rewrite the largest rectangle. This is the macro grammar;
    // Markov Junior's state chooses split position and later crop accents.
    // Parcel density follows physical area instead of stamping the same
    // topology into every footprint.
    footprint_area := plan.width * plan.height
    target_parcels := clamp((footprint_area + TARGET_PARCEL_CELLS - 1) / TARGET_PARCEL_CELLS, 1, PARCEL_CAPACITY)
    for plan.parcel_count < target_parcels {
        largest_index, largest_area := -1, 0
        for parcel, index in plan.parcels[:plan.parcel_count] {
            width, depth := parcel.max_x - parcel.min_x, parcel.max_z - parcel.min_z
            area := width * depth
            if area > largest_area && (width >= 7 || depth >= 7) {
                largest_index, largest_area = index, area
            }
        }
        if largest_index < 0 do break
        source := plan.parcels[largest_index]
        width, depth := source.max_x - source.min_x, source.max_z - source.min_z
        roll := variation_at(state, source.min_x + plan.parcel_count, source.min_z, seed)
        split_x := width > depth || (width == depth && roll > .5)
        if split_x && width < 7 do split_x = false
        if !split_x && depth < 7 do split_x = true
        span := split_x ? width : depth
        split_fraction := f32(.44 + roll * .12)
        if plan.tradition == .Ancient_Enclosure {
            split_fraction = .30 + roll * .40
        }
        inset := max(3, int(math.floor(f64(f32(span) * split_fraction))))
        inset = min(inset, span - 3)
        if inset < 3 do break
        a, b := source, source
        if split_x {
            a.max_x = source.min_x + inset
            b.min_x = a.max_x
        } else {
            a.max_z = source.min_z + inset
            b.min_z = a.max_z
        }
        plan.parcels[largest_index] = a
        append_parcel(&plan, b)
    }

    for &parcel, index in plan.parcels[:plan.parcel_count] {
        roll := mix(seed ~ u32(index + 1) * u32(0x9e3779b9))
        accent := variation_at(state, parcel.min_x, parcel.min_z, seed)
        parcel.crop = Crop((int(roll >> 8) + int(accent * 3)) % int(len(Crop)))
        parcel.row_axis_x = ((roll >> 16) & 1) != 0
        parcel.phase = f32(roll & 255) / 255
        parcel.tint = accent
    }
    // A kitchen garden is an embedded feature rather than a field parcel:
    // compact farms retain their single enclosure and large farms do not gain
    // an artificial hedge solely to separate household produce.
    plan.garden_span = clamp(min(plan.width, plan.height) / 5, 1, 3)
    plan.garden_x = (mix(seed ~ u32(0x47415244)) & 1) == 0 ? 1 : plan.width - plan.garden_span - 1
    plan.garden_z = (mix(seed ~ u32(0x4b495443)) & 1) == 0 ? 1 : plan.height - plan.garden_span - 1
    plan.valid = plan.parcel_count >= 1
    return plan
}

generate_sized :: proc(
    seed: u32,
    requested_width, requested_height: int,
    allocator := context.temp_allocator,
) -> Plan {
    tradition := Tradition.Ancient_Enclosure
    if (mix(seed ~ u32(0xa24baed5)) & 1) != 0 {
        tradition = .Parliamentary_Enclosure
    }
    return generate_sized_for_tradition(seed, requested_width, requested_height, tradition, allocator)
}

generate :: proc(seed: u32, allocator := context.temp_allocator) -> Plan {
    return generate_sized(seed, GRID_WIDTH, GRID_HEIGHT, allocator)
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil ||
       !plan.valid ||
       plan.parcel_count < 1 ||
       plan.width < MIN_GRID_SPAN ||
       plan.height < MIN_GRID_SPAN ||
       plan.width > MAX_GRID_SPAN ||
       plan.height > MAX_GRID_SPAN {
        return false
    }
    area := 0
    for parcel in plan.parcels[:plan.parcel_count] {
        if parcel.min_x < 0 ||
           parcel.min_z < 0 ||
           parcel.max_x > plan.width ||
           parcel.max_z > plan.height ||
           parcel.max_x <= parcel.min_x ||
           parcel.max_z <= parcel.min_z {
            return false
        }
        area += (parcel.max_x - parcel.min_x) * (parcel.max_z - parcel.min_z)
    }
    return area == plan.width * plan.height
}
