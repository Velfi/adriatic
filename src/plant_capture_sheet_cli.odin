package main

import plants "../packages/plants"
import "core:fmt"
import "core:image"
import _ "core:image/png"
import "core:os"
import "core:strings"
import stb_image "vendor:stb/image"
import stbtt "vendor:stb/truetype"

PLANT_SHEET_VIEW_SIZE :: 640
PLANT_SHEET_MARGIN :: 34
PLANT_SHEET_GAP :: 18
PLANT_SHEET_CARD_WIDTH :: 360
PLANT_SHEET_HEADER :: 112
PLANT_SHEET_WIDTH :: PLANT_SHEET_MARGIN * 2 + PLANT_SHEET_VIEW_SIZE * 3 + PLANT_SHEET_GAP * 3 + PLANT_SHEET_CARD_WIDTH
PLANT_SHEET_HEIGHT :: PLANT_SHEET_HEADER + PLANT_SHEET_VIEW_SIZE + PLANT_SHEET_MARGIN

Plant_Sheet_Color :: struct {
    r, g, b: u8,
}

plant_sheet_fill :: proc(pixels: []u8, x, y, width, height: int, color: Plant_Sheet_Color) {
    left, top := max(x, 0), max(y, 0)
    right, bottom := min(x + width, PLANT_SHEET_WIDTH), min(y + height, PLANT_SHEET_HEIGHT)
    for py in top ..< bottom {
        for px in left ..< right {
            at := (py * PLANT_SHEET_WIDTH + px) * 3
            pixels[at + 0], pixels[at + 1], pixels[at + 2] = color.r, color.g, color.b
        }
    }
}

plant_sheet_blit :: proc(pixels: []u8, source: ^image.Image, target_x, target_y: int) {
    width, height := min(source.width, PLANT_SHEET_VIEW_SIZE), min(source.height, PLANT_SHEET_VIEW_SIZE)
    for y in 0 ..< height {
        for x in 0 ..< width {
            source_at := (y * source.width + x) * source.channels
            target_at := ((target_y + y) * PLANT_SHEET_WIDTH + target_x + x) * 3
            if source.channels == 1 {
                value := source.pixels.buf[source_at]
                pixels[target_at + 0], pixels[target_at + 1], pixels[target_at + 2] = value, value, value
            } else {
                pixels[target_at + 0] = source.pixels.buf[source_at + 0]
                pixels[target_at + 1] = source.pixels.buf[source_at + 1]
                pixels[target_at + 2] = source.pixels.buf[source_at + 2]
            }
        }
    }
}

Plant_Sheet_Font :: struct {
    bitmap:     [512 * 512]u8,
    characters: [95]stbtt.bakedchar,
}

plant_sheet_font_load :: proc(font: ^Plant_Sheet_Font) -> bool {
    data, error := os.read_entire_file("assets/fonts/NotoSans-Regular.ttf", context.temp_allocator)
    if error != nil do return false
    return(
        stbtt.BakeFontBitmap(
            raw_data(data),
            0,
            28,
            raw_data(font.bitmap[:]),
            512,
            512,
            32,
            95,
            raw_data(font.characters[:]),
        ) >
        0 \
    )
}

plant_sheet_text :: proc(
    pixels: []u8,
    font: ^Plant_Sheet_Font,
    text: string,
    x, baseline: f32,
    color: Plant_Sheet_Color,
    scale := f32(1),
) {
    cursor_x, cursor_y := f32(0), f32(0)
    for value in text {
        if value < 32 || value > 126 do continue
        quad: stbtt.aligned_quad
        stbtt.GetBakedQuad(raw_data(font.characters[:]), 512, 512, i32(value - 32), &cursor_x, &cursor_y, &quad, false)
        x0, y0 := int(x + quad.x0 * scale), int(baseline + quad.y0 * scale)
        width := max(int((quad.x1 - quad.x0) * scale), 1)
        height := max(int((quad.y1 - quad.y0) * scale), 1)
        source_x0, source_y0 := int(quad.s0 * 512), int(quad.t0 * 512)
        source_width, source_height := max(int((quad.s1 - quad.s0) * 512), 1), max(int((quad.t1 - quad.t0) * 512), 1)
        for py in 0 ..< height {
            target_y := y0 + py
            if target_y < 0 || target_y >= PLANT_SHEET_HEIGHT do continue
            source_y := source_y0 + py * source_height / height
            for px in 0 ..< width {
                target_x := x0 + px
                if target_x < 0 || target_x >= PLANT_SHEET_WIDTH do continue
                source_x := source_x0 + px * source_width / width
                alpha := font.bitmap[source_y * 512 + source_x]
                if alpha == 0 do continue
                at := (target_y * PLANT_SHEET_WIDTH + target_x) * 3
                inverse := 255 - u16(alpha)
                pixels[at + 0] = u8((u16(pixels[at + 0]) * inverse + u16(color.r) * u16(alpha)) / 255)
                pixels[at + 1] = u8((u16(pixels[at + 1]) * inverse + u16(color.g) * u16(alpha)) / 255)
                pixels[at + 2] = u8((u16(pixels[at + 2]) * inverse + u16(color.b) * u16(alpha)) / 255)
            }
        }
    }
}

plant_sheet_habit_name :: proc(habit: plants.Growth_Habit) -> string {
    switch habit {
    case .Free_Standing:
        return "free-standing"
    case .Wall_Trained:
        return "wall-trained"
    case .Trellised:
        return "trellised"
    }
    return "unknown"
}

plant_sheet_compose :: proc(species: plants.Species, seed: u64, frames: [3]string, output: string) -> bool {
    pixels, allocation_error := make([]u8, PLANT_SHEET_WIDTH * PLANT_SHEET_HEIGHT * 3)
    if allocation_error != nil do return false
    defer delete(pixels)
    background := Plant_Sheet_Color{23, 27, 24}
    text := Plant_Sheet_Color{239, 236, 215}
    muted := Plant_Sheet_Color{143, 164, 143}
    plant_sheet_fill(pixels, 0, 0, PLANT_SHEET_WIDTH, PLANT_SHEET_HEIGHT, background)
    labels := [3]string{"FRONT", "SIDE", "TOP"}
    x := PLANT_SHEET_MARGIN
    for frame, index in frames {
        source, load_error := image.load(frame)
        if load_error != nil || source == nil {
            fmt.eprintf("plant sheet: cannot load %s: %v\n", frame, load_error)
            return false
        }
        plant_sheet_blit(pixels, source, x, PLANT_SHEET_HEADER)
        image.destroy(source)
        plant_sheet_fill(pixels, x, PLANT_SHEET_HEADER, 92, 36, background)
        x += PLANT_SHEET_VIEW_SIZE + PLANT_SHEET_GAP
    }
    plant_sheet_fill(
        pixels,
        x,
        PLANT_SHEET_HEADER,
        PLANT_SHEET_CARD_WIDTH,
        PLANT_SHEET_VIEW_SIZE,
        Plant_Sheet_Color{38, 45, 39},
    )
    font, font_error := new(Plant_Sheet_Font)
    if font_error != nil do return false
    defer free(font)
    if !plant_sheet_font_load(font) {
        fmt.eprintln("plant sheet: could not load the bundled font")
        return false
    }
    name := plants.species_name(species)
    plant_sheet_text(pixels, font, name, PLANT_SHEET_MARGIN, 58, text, 1.25)
    plant_sheet_text(
        pixels,
        font,
        fmt.tprintf("SEED %d  /  MATURE  /  NEAR DETAIL", seed),
        PLANT_SHEET_MARGIN,
        88,
        muted,
        .64,
    )
    x = PLANT_SHEET_MARGIN
    for label in labels {
        plant_sheet_text(pixels, font, label, f32(x + 12), PLANT_SHEET_HEADER + 29, text, .72)
        x += PLANT_SHEET_VIEW_SIZE + PLANT_SHEET_GAP
    }
    card_x := x + 28
    plant_sheet_text(pixels, font, "PLANT", f32(card_x), PLANT_SHEET_HEADER + 53, muted, .62)
    plant_sheet_text(pixels, font, name, f32(card_x), PLANT_SHEET_HEADER + 88, text, .72)
    keys := [5]string{"HABIT", "MATURITY", "DETAIL", "SEED", "VIEWS"}
    values := [5]string {
        plant_sheet_habit_name(plants.default_habit(species)),
        "100%",
        "near",
        fmt.tprintf("%d", seed),
        "front / side / top",
    }
    y := PLANT_SHEET_HEADER + 150
    for key, index in keys {
        plant_sheet_text(pixels, font, key, f32(card_x), f32(y), muted, .58)
        plant_sheet_text(pixels, font, values[index], f32(card_x), f32(y + 30), text, .68)
        y += 78
    }
    output_cstring, cstring_error := strings.clone_to_cstring(output, context.temp_allocator)
    if cstring_error != nil do return false
    return(
        stb_image.write_png(
            output_cstring,
            PLANT_SHEET_WIDTH,
            PLANT_SHEET_HEIGHT,
            3,
            raw_data(pixels),
            PLANT_SHEET_WIDTH * 3,
        ) !=
        0 \
    )
}

adriatic_cli_plant_sheet :: proc(args: []string) -> bool {
    if len(args) < 3 {
        fmt.eprintln(
            "usage: adriatic plant-sheet <species> [--output output.png] [--seed n] [--keep-frames] [--reuse-frames directory]",
        )
        return false
    }
    species_index := plant_generator_find_species(args[2])
    if species_index < 0 {
        fmt.eprintf("adriatic: unknown plant species: %s\n", args[2])
        return false
    }
    output := "build/captures/plant-sheet.png"
    seed := u64(73)
    keep_frames := false
    reuse_frames := ""
    index := 3
    for index < len(args) {
        switch args[index] {
        case "--keep-frames":
            keep_frames = true
            index += 1
        case "--output", "--seed", "--reuse-frames":
            if index + 1 >= len(args) {
                fmt.eprintf("adriatic: %s requires a value\n", args[index])
                return false
            }
            if args[index] == "--output" {
                output = args[index + 1]
            } else if args[index] == "--reuse-frames" {
                reuse_frames = args[index + 1]
            } else {
                parsed, ok := adriatic_cli_parse_bounded_int("--seed", args[index + 1], 0, 0x7fffffff)
                if !ok do return false
                seed = u64(parsed)
            }
            index += 2
        case:
            fmt.eprintf("adriatic: unknown plant-sheet option: %s\n", args[index])
            return false
        }
    }
    absolute_output, resolved := adriatic_cli_absolute_path(output)
    if !resolved do return false
    parent := os.dir(absolute_output)
    if error := os.make_directory_all(parent); error != nil && error != .Exist {
        fmt.eprintf("plant sheet: cannot create output directory: %v\n", error)
        return false
    }
    frames_directory := fmt.tprintf(
        "%s/%s-frames",
        parent,
        os.base(absolute_output[:len(absolute_output) - len(os.ext(absolute_output))]),
    )
    if reuse_frames != "" {
        resolved_frames, frames_resolved := adriatic_cli_absolute_path(reuse_frames)
        if !frames_resolved do return false
        frames_directory = resolved_frames
    } else {
        capture_args := [16]string {
            args[0],
            "capture",
            "plant-generator",
            "--output",
            frames_directory,
            "--target",
            fmt.tprintf("%s-sheet", args[2]),
            "--width",
            "640",
            "--height",
            "640",
            "--settle-frames",
            "4",
            "--plant-sheet-views",
            "--seed-start",
            fmt.tprintf("%d", seed),
        }
        _, captured := adriatic_cli(capture_args[:])
        if !captured do return false
    }
    frames := [3]string {
        fmt.tprintf("%s/front.png", frames_directory),
        fmt.tprintf("%s/side.png", frames_directory),
        fmt.tprintf("%s/top.png", frames_directory),
    }
    if !plant_sheet_compose(plants.Species(species_index), seed, frames, absolute_output) do return false
    manifest := fmt.tprintf(
        "{\n  \"species\": \"%s\",\n  \"seed\": %d,\n  \"maturity\": 1.0,\n  \"detail\": \"near\",\n  \"views\": [\"front\", \"side\", \"top\"],\n  \"output\": \"%s\"\n}\n",
        args[2],
        seed,
        absolute_output,
    )
    manifest_path := fmt.tprintf("%s.json", absolute_output[:len(absolute_output) - len(os.ext(absolute_output))])
    if error := os.write_entire_file(manifest_path, transmute([]byte)manifest); error != nil {
        fmt.eprintf("plant sheet: cannot write manifest: %v\n", error)
        return false
    }
    if !keep_frames && reuse_frames == "" do _ = os.remove_all(frames_directory)
    fmt.println(absolute_output)
    return true
}
