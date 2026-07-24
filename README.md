# Adriatic

An Odin game project built on [Zelda Engine](../zelda-engine).

## Layout

```text
parent-directory/
├── adriatic/
└── zelda-engine/
```

`src/` contains the executable and presentation layer. Put game-specific rules
in `packages/` as the project grows. Zelda Engine remains a reusable sibling
dependency and is imported through the `zelda_engine` collection.

## Quick start

```sh
make doctor
make run
```

`ZELDA_ENGINE_ROOT` overrides the default sibling-engine location. The project
uses the same pinned Odin toolchain contract as Last Best Hope; run
`make bootstrap` on macOS when the local toolchain is not already installed.
Jolt Physics is provisioned automatically from Zelda Engine's pinned source
checkout when building, releasing, or testing Adriatic.

## Everyday commands

| Command | Purpose |
| --- | --- |
| `make fmt` | Format Odin sources. |
| `make check` | Type-check the application. |
| `make test` | Run starter tests. |
| `make run` | Build and run the development executable. |
| `make release` | Build an optimized executable. |
| `make physics-build` | Fetch and build Zelda Engine's pinned Jolt dependency. |
