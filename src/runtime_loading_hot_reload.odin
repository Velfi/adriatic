package main

import engine_sound "../packages/engine_sound"
import postale_game "../packages/postale"
import roads "../packages/roads"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:time"
import timezone "core:time/timezone"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

hot_reload_requested :: proc(library_path: string, loaded_mtime: i64) -> bool {
    if library_path == "" do return false
    modified, err := os.modification_time_by_path(library_path)
    if err != nil do return false
    modified_mtime := time.time_to_unix_nano(modified)
    return modified_mtime > loaded_mtime
}

Loading_Postcard_Period :: enum {
    Dawn,
    Morning,
    Midday,
    Golden_Hour,
    Dusk,
    Night,
}

loading_postcard_period_for_hour :: proc(hour: int) -> Loading_Postcard_Period {
    normalized_hour := ((hour % 24) + 24) % 24
    switch normalized_hour {
    case 4 ..= 6:
        return .Dawn
    case 7 ..= 10:
        return .Morning
    case 11 ..= 15:
        return .Midday
    case 16 ..= 18:
        return .Golden_Hour
    case 19 ..= 21:
        return .Dusk
    case:
        return .Night
    }
}

loading_postcard_period_from_name :: proc(name: string) -> (Loading_Postcard_Period, bool) {
    switch name {
    case "dawn":
        return .Dawn, true
    case "morning":
        return .Morning, true
    case "midday":
        return .Midday, true
    case "golden-hour", "golden":
        return .Golden_Hour, true
    case "dusk":
        return .Dusk, true
    case "night":
        return .Night, true
    case:
        return {}, false
    }
}

loading_postcard_path :: proc(period: Loading_Postcard_Period) -> string {
    switch period {
    case .Dawn:
        return "assets/textures/ui/loading-postcard-dawn.png"
    case .Morning:
        return "assets/textures/ui/loading-postcard-morning.png"
    case .Midday:
        return "assets/textures/ui/loading-postcard-midday.png"
    case .Golden_Hour:
        return "assets/textures/ui/loading-postcard-golden-hour.png"
    case .Dusk:
        return "assets/textures/ui/loading-postcard-dusk.png"
    case .Night:
        return "assets/textures/ui/loading-postcard-night.png"
    }
    return "assets/textures/ui/loading-postcard-midday.png"
}

loading_postcard_local_hour :: proc() -> int {
    now := time.now()
    utc_datetime, datetime_ok := time.time_to_datetime(now)
    if !datetime_ok {
        hour, _, _ := time.clock(now)
        return hour
    }
    local_region, region_ok := timezone.region_load("local", context.temp_allocator)
    if !region_ok {
        hour, _, _ := time.clock(now)
        return hour
    }
    defer timezone.region_destroy(local_region, context.temp_allocator)
    local_datetime, local_ok := timezone.datetime_to_tz(utc_datetime, local_region)
    if !local_ok {
        hour, _, _ := time.clock(now)
        return hour
    }
    return int(local_datetime.hour)
}
