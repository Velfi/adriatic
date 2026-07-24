# Adriatic contributor notes

- `zelda-engine` is a sibling dependency and must remain product-neutral.
- Keep product rules, assets, and presentation policy in this repository.
- Use the `zelda_engine` Odin collection instead of relative imports into the engine.

## Screenshot capture

- Run `make capture` from the repository root to build the app, render several
  frames, save `build/captures/adriatic.png`, and exit automatically.
- To choose another destination, pass an absolute path:
  `make capture CAPTURE_PATH=/absolute/path/to/screenshot.png`.
- Capture launches the macOS app briefly. In a sandboxed agent environment,
  allow GUI execution and sibling `../zelda-engine` build writes when prompted.
