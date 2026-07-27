package main

import "core:testing"

when ODIN_TEST {
    @(test)
    loading_postcard_period_covers_every_local_hour :: proc(t: ^testing.T) {
        expected := [24]Loading_Postcard_Period {
            .Night, // 00
            .Night,
            .Night,
            .Night,
            .Dawn, // 04
            .Dawn,
            .Dawn,
            .Morning, // 07
            .Morning,
            .Morning,
            .Morning,
            .Midday, // 11
            .Midday,
            .Midday,
            .Midday,
            .Midday,
            .Golden_Hour, // 16
            .Golden_Hour,
            .Golden_Hour,
            .Dusk, // 19
            .Dusk,
            .Dusk,
            .Night, // 22
            .Night,
        }
        for period, hour in expected {
            testing.expect(t, loading_postcard_period_for_hour(hour) == period)
        }
        testing.expect(t, loading_postcard_period_for_hour(-1) == .Night)
        testing.expect(t, loading_postcard_period_for_hour(24) == .Night)
    }

    @(test)
    loading_postcard_names_and_paths_cover_every_period :: proc(t: ^testing.T) {
        names := [6]string{"dawn", "morning", "midday", "golden-hour", "dusk", "night"}
        for name, expected in names {
            period, known := loading_postcard_period_from_name(name)
            testing.expect(t, known)
            testing.expect(t, int(period) == expected)
            testing.expect(t, loading_postcard_path(period) != "")
        }
        _, known := loading_postcard_period_from_name("afternoon")
        testing.expect(t, !known)
    }
}
