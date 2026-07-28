# Architectural materials

These neutral grayscale textures are intended to be multiplied by the
architecture palette at render time. They contain no baked product color.

| Texture | Suggested use | Nominal coverage | Roughness |
| --- | --- | ---: | ---: |
| `lime-plaster.png` | Exterior plaster and stucco | 2 m square | 0.88 |
| `cut-limestone.png` | Foundations, retaining walls, and trim | 4 m square | 0.82 |
| `barrel-roof-tile.png` | Pitched Mediterranean roofs | 4 m square | 0.76 |

All maps are 1024 × 1024, 8-bit single-channel grayscale PNGs. Use repeat
addressing and sample them as linear data when they modulate a linearized base
color.

`material-atlas.png` packs the three maps horizontally in the table order for
the Vulkan world shader. The individual maps remain the editable sources.

## Generation

Provider: built-in OpenAI image generation  
Execution mode: one generation per material, followed by local grayscale
conversion and resizing.

The prompts requested orthographic, edge-to-edge, seamless game textures with
flat diffuse lighting, neutral grayscale values, no text, and no watermark.
Material-specific subjects were fine lime plaster, hand-cut Adriatic limestone
ashlar, and overlapping Mediterranean barrel roof tiles.
