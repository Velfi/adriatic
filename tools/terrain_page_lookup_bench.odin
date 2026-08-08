package main

import terrain "../packages/terrain"
import "core:fmt"
import "core:time"

legacy_page_count :: proc(project: ^terrain.Project, level: int, min_x, min_z, max_x, max_z: f32) -> int {
    layout := project.terrain_level_layout[level]
    extent := f32(terrain.TERRAIN_PAGE_RESOLUTION) * layout.cell_size
    count := 0
    for page in project.terrain_pages {
        if int(page.level) != level do continue
        px := layout.origin_x + f32(page.page_x) * extent
        pz := layout.origin_z + f32(page.page_z) * extent
        if px > max_x || pz > max_z || px + extent < min_x || pz + extent < min_z do continue
        count += 1
    }
    return count
}

main :: proc() {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    pages_axis := terrain.TERRAIN_RESOLUTION / terrain.TERRAIN_PAGE_RESOLUTION
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        project.terrain_level_layout[level] = {1, -256, -256}
        for page_z in 0 ..< pages_axis {
            for page_x in 0 ..< pages_axis {
                append(
                    &project.terrain_pages,
                    terrain.Terrain_Page{level = u8(level), page_x = u8(page_x), page_z = u8(page_z)},
                )
            }
        }
    }
    terrain.terrain_sampling_lookup_rebuild(project)
    result: [256]int
    iterations := 100_000
    sink := 0
    started := time.now()
    for _ in 0 ..< iterations do sink += legacy_page_count(project, 0, -32, -32, 32, 32)
    legacy := time.since(started)
    started = time.now()
    for _ in 0 ..< iterations do sink += terrain.terrain_page_indices_in_bounds(project, 0, -32, -32, 32, 32, result[:])
    bounded := time.since(started)
    fmt.printf(
        "pages=%d iterations=%d legacy=%v bounded=%v speedup=%.2fx checksum=%d\n",
        len(project.terrain_pages),
        iterations,
        legacy,
        bounded,
        f64(legacy) / f64(bounded),
        sink,
    )
}
