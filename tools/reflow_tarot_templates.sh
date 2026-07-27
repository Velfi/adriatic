#!/bin/sh
set -eu

asset_dir="assets/textures/ui/tarot-nanobanana"
card_w=108
card_h=158
background="#1b102b"

reflow() {
    source_image="$1"
    output_image="$2"
    source_cols="$3"
    source_x="$4"
    source_y="$5"
    source_pitch_x="$6"
    source_pitch_y="$7"
    card_count="$8"
    output_cols="$9"

    output_rows=$(( (card_count + output_cols - 1) / output_cols ))
    output_w=$((output_cols * card_w))
    output_h=$((output_rows * card_h))
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT INT TERM

    magick -size "${output_w}x${output_h}" "xc:${background}" "$tmp_dir/canvas.png"

    index=0
    while [ "$index" -lt "$card_count" ]; do
        source_col=$((index % source_cols))
        source_row=$((index / source_cols))
        crop_x=$((source_x + source_col * source_pitch_x))
        crop_y=$((source_y + source_row * source_pitch_y))
        output_x=$(((index % output_cols) * card_w))
        output_y=$(((index / output_cols) * card_h))

        magick "$source_image" \
            -crop "${card_w}x${card_h}+${crop_x}+${crop_y}" +repage \
            "$tmp_dir/card.png"
        magick "$tmp_dir/canvas.png" "$tmp_dir/card.png" \
            -geometry "+${output_x}+${output_y}" -composite \
            "$tmp_dir/next.png"
        mv "$tmp_dir/next.png" "$tmp_dir/canvas.png"
        index=$((index + 1))
    done

    mv "$tmp_dir/canvas.png" "$output_image"
    rm -rf "$tmp_dir"
    trap - EXIT INT TERM
}

# Trumps source is an edge-to-edge 11x2 grid of 108x158 cards.
reflow \
    "$asset_dir/template-trumps.png" \
    "$asset_dir/template-trumps-6x4.png" \
    11 0 0 108 158 22 6

# Suit sources are padded 7x2 grids with 4px left, 98px top, and 108/158 pitch.
for suit in wands cups swords pentacles; do
    reflow \
        "$asset_dir/template-${suit}-7x2.png" \
        "$asset_dir/template-${suit}-5x3.png" \
        7 4 98 108 158 14 5
done
