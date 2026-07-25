# Adriatic contributor notes

- `zelda-engine` is a sibling dependency and must remain product-neutral.
- Keep product rules, assets, and presentation policy in this repository.
- Use the `zelda_engine` Odin collection instead of relative imports into the engine.

## Screenshot capture

- Run `make capture` from the repository root to build the app, render several
  frames, save `build/captures/adriatic.png`, and exit automatically.
- To choose another destination, pass an absolute path:
  `make capture CAPTURE_PATH=/absolute/path/to/screenshot.png`.
- Run `make capture-building` for a clean, eye-level architectural capture.
  It automatically selects and frames a façade; pass a zero-based architecture
  ordinal with `CAPTURE_TARGET=3` to target a specific generated building, or
  use `CAPTURE_TARGET=cypress` for a close cypress streetscape view.
- Capture launches the macOS app briefly. In a sandboxed agent environment,
  allow GUI execution and sibling `../zelda-engine` build writes when prompted.
