# Photo filter media atlas

`clean-room-media-atlas.png` is an original Adriatic shader resource generated
with OpenAI's built-in image generation tool on 2026-07-31. No upstream image
was supplied as a reference and no texture from `jhaakma/joy-of-painting` was
copied or transformed.

The atlas contains nine monochrome cells (noise, grain, charcoal, hatch, paper,
pastel, mottle, splash, and canvas) followed by nine color-grade swatches. It is
used as consumer-defined auxiliary input by Photo Mode's clean-room shaders.

The effect names and broad visual goals are inspired by the public
`jhaakma/joy-of-painting` catalog. That repository did not declare a source or
asset license when this work was authored, so its shader text and bitmap assets
are intentionally not redistributed here.

Generation prompt summary: a strict technical atlas of seamless handmade-media
surfaces and color-grade swatches, with no text, objects, perspective, copied
game assets, or watermark.

`clean-room-lut-atlas.png` is a deterministic 3x3 collection of original
8x8x8 color cubes: neutral, warm, cool, saturated, desaturated, sepia, pastel,
radioactive, and hue-shifted. It was generated from mathematical color
transforms and contains no upstream pixels.
