# Release pipeline

Adriatic publishes macOS and Windows x64 archives from GitHub Actions. Run the
release helper from a clean `main` branch that is synchronized with
`origin/main`:

```sh
scripts/release.sh 0.1.0
```

The helper validates the version, checks for existing tags, creates an
annotated `v<version>` tag, and asks before pushing it. You can also run the
**Release** workflow manually against an existing tag.

The coordinator in `.github/workflows/release.yml` calls the reusable macOS
and Windows workflows, waits for both artifacts, and creates a GitHub Release
with generated notes. Tags with a SemVer prerelease suffix, such as
`v0.2.0-beta.1`, create a prerelease.

If a release tag must be corrected to point at the current commit, use the
explicit retag helper:

```sh
scripts/retag-head.sh 0.1.0
```

This rewrites and force-pushes the named tag, so use it only when replacing a
mistaken release tag is intentional.

Both builders check out Zelda Engine separately. By default they use
`Velfi/zelda-engine` at `main`. Set these repository variables to override it:

- `ZELDA_ENGINE_REPOSITORY`
- `ZELDA_ENGINE_REF`

If Zelda Engine is private, set `ZELDA_ENGINE_TOKEN` to a token that can read
it.

## macOS signing and notarization

Without Apple secrets, the workflow still emits an unsigned `Adriatic.app`
ZIP. To sign and notarize it, configure:

- `APPLE_CERTIFICATE`: base64-encoded Developer ID Application `.p12`
- `APPLE_CERTIFICATE_PASSWORD`: password for that certificate
- `APPLE_API_KEY_CONTENT`: contents of an App Store Connect `.p8` API key
- `APPLE_API_KEY`: API key ID
- `APPLE_API_ISSUER`: issuer UUID

The package includes its Homebrew dylib closure, MoltenVK, the Zelda Engine
physics bridge, assets, and compiled shaders. The default bundle identifier is
`com.velfi.adriatic`; set the `MACOS_BUNDLE_ID` environment variable when
running `scripts/package_macos.sh` locally to override it.

## Windows

The Windows workflow builds the pinned Adriatic Odin fork, installs SDL3,
Vulkan, HarfBuzz, and FreeType through vcpkg, builds Zelda Engine's Jolt bridge,
and emits `Adriatic-windows.zip`. The archive contains the executable, runtime
DLL closure, assets, and compiled shaders.

The current pipeline publishes a portable ZIP rather than an MSIX. Windows
code-signing or Store packaging can be added later without changing the release
coordinator.
