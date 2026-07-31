# Terrain particle atlas

`terrain-particle-atlas.png` is an 8 × 6 RGBA sprite atlas. UV cells are
uniform: `u = column / 8`, `v = row / 6`, with rows authored from the top.

| Row | Terrain | Variants |
| ---: | --- | ---: |
| 0 | Grass | 8 |
| 1 | Asphalt | 8 |
| 2 | Gravel | 8 |
| 3 | Cobblestone | 8 |
| 4 | Dirt | 8 |
| 5 | Sand | 8 |

The source chroma-key render is retained as
`terrain-particle-atlas-source.png`. Runtime code should use the alpha atlas,
not the source image.
