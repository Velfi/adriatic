package terrain

import "core:math"

CLIPMAP_LEVELS :: 5
WORLD_SIZE_METERS :: 4000.0
RING_RESOLUTION :: 256
SAMPLES_PER_LEVEL :: RING_RESOLUTION * RING_RESOLUTION
BASE_CELL_SIZE :: WORLD_SIZE_METERS / f32(RING_RESOLUTION - 1)

// These are expressed as a fraction of the authored world's half extent. Every
// clipmap level samples the same world-space features at a different density.
DEFAULT_ISLAND_OFFSET :: 0.65
DEFAULT_ISLAND_RADIUS :: 0.14
DEFAULT_ISLAND_HEIGHT :: 4.5
DEFAULT_ISLAND_SIGNS :: [2]f32{-1, 1}
DEFAULT_RUNWAY_HALF_LENGTH :: 0.10
DEFAULT_RUNWAY_HALF_WIDTH :: 0.012
DEFAULT_RUNWAY_SPAWN_OFFSET :: 0.06
DEFAULT_PIER_INNER_OFFSET :: 0.10

Tool :: enum {
	Raise,
	Smooth,
	Paint,
}

Clipmap_Level :: struct {
	cell_size: f32,
	heights:   [SAMPLES_PER_LEVEL]f32,
	material:  [SAMPLES_PER_LEVEL]f32,
}

Project :: struct {
	levels:    [CLIPMAP_LEVELS]Clipmap_Level,
	sea_level: f32,
	revision:  u64,
}

init_project :: proc(result: ^Project) {
	if result == nil do return
	result^ = {}
	result.sea_level = 0
	result.revision = 1
	authored_half_extent := f32(WORLD_SIZE_METERS * .5)
	for level in 0 ..< CLIPMAP_LEVELS {
		data := &result.levels[level]
		data.cell_size = BASE_CELL_SIZE * f32(math.pow(2, f64(level)))
		for z in 0 ..< RING_RESOLUTION {
			for x in 0 ..< RING_RESOLUTION {
				world_x := (f32(x) - f32(RING_RESOLUTION - 1) * .5) * data.cell_size
				world_z := (f32(z) - f32(RING_RESOLUTION - 1) * .5) * data.cell_size
				data.heights[sample_index(x, z)] = default_height(
					world_x,
					world_z,
					authored_half_extent,
				)
			}
		}
	}
}

new_project :: proc() -> Project {
	result: Project
	init_project(&result)
	return result
}

sample_index :: proc(x, z: int) -> int {return z * RING_RESOLUTION + x}

default_height :: proc(world_x, world_z, half_extent: f32) -> f32 {
	radius := half_extent * DEFAULT_ISLAND_RADIUS
	for sign in DEFAULT_ISLAND_SIGNS {
		center_x := sign * half_extent * DEFAULT_ISLAND_OFFSET
		center_z := sign * half_extent * DEFAULT_ISLAND_OFFSET
		dx, dz := world_x - center_x, world_z - center_z
		distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
		if distance < radius {
			// A broad, flat top leaves enough usable land for the runway while
			// the outer third falls cleanly into the sea.
			falloff := clamp((radius - distance) / (radius * .34), 0, 1)
			return DEFAULT_ISLAND_HEIGHT * (.58 + falloff * .42)
		}
	}
	return 0
}

// sample_height returns a bilinear local sample. The MVP keeps an editable
// window per hierarchy level; world-space ring snapping keeps that window
// centered beneath the author while the ocean remains unbounded.
sample_height :: proc(project: ^Project, level: int, x, z: f32) -> f32 {
	if project == nil || level < 0 || level >= CLIPMAP_LEVELS do return 0
	data := &project.levels[level]
	grid_x := x / data.cell_size + f32(RING_RESOLUTION - 1) * .5
	grid_z := z / data.cell_size + f32(RING_RESOLUTION - 1) * .5
	x0 := clamp(int(math.floor(f64(grid_x))), 0, RING_RESOLUTION - 1)
	z0 := clamp(int(math.floor(f64(grid_z))), 0, RING_RESOLUTION - 1)
	x1 := min(x0 + 1, RING_RESOLUTION - 1)
	z1 := min(z0 + 1, RING_RESOLUTION - 1)
	tx := clamp(grid_x - f32(x0), 0, 1)
	tz := clamp(grid_z - f32(z0), 0, 1)
	a := data.heights[sample_index(x0, z0)] * (1 - tx) + data.heights[sample_index(x1, z0)] * tx
	b := data.heights[sample_index(x0, z1)] * (1 - tx) + data.heights[sample_index(x1, z1)] * tx
	return a * (1 - tz) + b * tz
}

sample_material :: proc(project: ^Project, level: int, x, z: f32) -> f32 {
	if project == nil || level < 0 || level >= CLIPMAP_LEVELS do return 0
	data := &project.levels[level]
	grid_x := clamp(
		int(math.round(f64(x / data.cell_size + f32(RING_RESOLUTION - 1) * .5))),
		0,
		RING_RESOLUTION - 1,
	)
	grid_z := clamp(
		int(math.round(f64(z / data.cell_size + f32(RING_RESOLUTION - 1) * .5))),
		0,
		RING_RESOLUTION - 1,
	)
	return data.material[sample_index(grid_x, grid_z)]
}

apply_stroke :: proc(
	project: ^Project,
	tool: Tool,
	world_x, world_z, radius, strength, direction: f32,
) {
	if project == nil || radius <= 0 || strength <= 0 do return
	for level in 0 ..< CLIPMAP_LEVELS {
		data := &project.levels[level]
		// Coarse levels receive a footprint no smaller than their sampling cell so
		// an authoring stroke remains represented at every clipmap resolution.
		effective_radius := max(radius, data.cell_size * 1.5)
		for z in 0 ..< RING_RESOLUTION {
			for x in 0 ..< RING_RESOLUTION {
				world_sample_x := (f32(x) - f32(RING_RESOLUTION - 1) * .5) * data.cell_size
				world_sample_z := (f32(z) - f32(RING_RESOLUTION - 1) * .5) * data.cell_size
				dx, dz := world_sample_x - world_x, world_sample_z - world_z
				distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
				if distance > effective_radius do continue
				falloff := 1 - distance / effective_radius
				index := sample_index(x, z)
				switch tool {
				case .Raise:
					data.heights[index] += direction * strength * falloff * data.cell_size
				case .Paint:
					data.material[index] = clamp(
						data.material[index] + direction * strength * falloff,
						0,
						1,
					)
				case .Smooth:
					left := data.heights[sample_index(max(x - 1, 0), z)]
					right := data.heights[sample_index(min(x + 1, RING_RESOLUTION - 1), z)]
					up := data.heights[sample_index(x, max(z - 1, 0))]
					down := data.heights[sample_index(x, min(z + 1, RING_RESOLUTION - 1))]
					average := (left + right + up + down) * .25
					data.heights[index] +=
						(average - data.heights[index]) * clamp(strength * falloff, 0, 1)
				}
			}
		}
	}
	project.revision += 1
}
