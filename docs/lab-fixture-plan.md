# Lab fixture conversion

## Goal

Make a fixture a reliable Dunes playground: save its three authoring knobs,
restore the Dunes scene after load, and rebuild only derived Dunes runtime
state without mutating the saved terrain snapshot.

## Scope

This pass converts Dunes only. The lab inventory shows that every other lab is
either a renderer/debug/asset-preview session, or already stores its authored
world state in `Fixture` (wrecks, farms, marina/harbor, settlement, vehicle
state). They need individual product decisions before receiving new fixture
schema.

## Milestones

1. **Typed lab boundary and v8 migration** — replace serialized legacy
   `Fixture.active_lab_scene` with `Fixture.lab`, containing a stable lab kind
   and Dunes `{seed, wind_angle, vegetation}`. Keep active scene identity and
   all generated data root-side. Freeze v8 manifest/history, generate the
   7→8 scaffold, and migrate every v7 legacy string to `.None`: v7 never saved
   the Dunes knobs and its loader rejects all nonempty legacy strings.
   Acceptance: v1→v8 and v7→v8 chains are contiguous; v8 Dunes config codec
   round-trips exactly.
2. **Dunes runtime rehydration** — replace Dunes globals with root Editor
   runtime state, derive plan/shore/diagnostics from the typed config, and
   activate Dunes after fixture or hot-state load. Rehydration must preserve
   the decoded terrain bytes; input changes continue to regenerate terrain.
   Exiting Dunes clears typed lab state and runtime.
   Acceptance: a Dunes fixture reopens Dunes with usable plan/shore while its
   terrain snapshot is unchanged; normal loads clear stale lab runtime.
3. **Hostile and integration proof** — preflight unknown lab kinds, non-finite
   values, and out-of-range Dunes controls atomically. Prove direct/chained
   migration defaults, codec determinism, Editor load/store, lifecycle, hot
   reload rehydration, and zero leaks.
   Acceptance: all fixture gates, schema/history/scaffold checks, and `make
   check` pass; frozen v7 artifacts remain byte-identical.

## Current phase

Milestone 3 implementation complete — focused proof is green; the constrained
host stopped the full container runner after startup, so its result remains
unclaimed.

## M1 evidence — typed boundary and v8 migration

- `Fixture.lab` is `Lab_Fixture_State`: `Lab_Kind {None, Dunes}` plus
  `Dunes_Lab_Config {seed: u32, wind_angle: f32, vegetation: f32}`.
  `Editor.active_lab_scene` remains root-side and is `fixture:"-"`.
- Schema v7 → v8 diff is six changes: three state changes (`Fixture.lab` add,
  `Fixture.active_lab_scene` removal, and required field order), plus the three
  supporting types. The v7 → v8 scaffold is generated and fully resolved.
- Adjacent step is registered as production step seven. It decodes frozen v7
  only for a direct v7 source, deliberately discards every legacy scene string
  (including `"dunes"`), and writes exact `.None` plus zero Dunes config.
  Older chains take the same default path without pretending their payload is
  v7.
- Frozen v7 schema/history remain unchanged:
  `adb3ca76b334cba6fbd631ec59b28428dd4b1a629ac38ae5a5ee3400a6b05c3c` /
  `d59d3d0d103ba139c4a38ddb3fc55ac45a993cc42300704d5e4f6748e2ede8ef`.
  New v8 schema/history are deterministic across two generations:
  `c5772bf9732b7241c4230f954ebc8b3f8b1d3cb083efeced0666d00538bcb68a` /
  `6689bf8a5d3bf4bbc1c30eb29856d3db85807b9b565f78488c31da94c7ce5a78`.
- v8 manifest has 1,962 lines; generated v8 history has 2,578 lines.
  Resolved 7 → 8 migration source SHA is
  `cbfe7cf582ea84c9e72d141803e979460868c4c0e378ad2ce42434a136343f6a`.
- Passed: schema check; v8 history check; v7 → v8 scaffold check; two schema
  generations; two v8 history generations; `make check`; focused direct v7 →
  v8 and chained v1 → v8 migration proof (1/1, zero leaks); fixture codec
  (2/2, zero leaks) including exact typed Dunes config round-trip.
- The broad migration and Editor-load runner processes were host-killed after
  test-runner startup before reporting a test result, including with one test
  thread. This is the existing large-fixture/OOM memory ceiling, not an M1
  assertion failure; the focused compatibility proof above is green.

## M2 evidence — Dunes runtime rehydration

- The six former Dunes globals are gone. `Editor.dunes_lab_runtime` is
  `hs:"-"` root runtime containing only `plan`, `shore`, and diagnostics;
  `Fixture.lab.dunes` remains the sole durable source for seed, wind, and
  vegetation.
- Fresh Dunes entry writes default typed config (with an optional seed target)
  before regenerating terrain. Dunes input mutates that typed config and then
  regenerates. The registered Dunes exit clears both config and runtime.
- Fixture and hot-state load call `dunes_lab_rehydrate`, which rebuilds plan,
  shore, diagnostics, and the root active scene only. It does not call the lab
  loader/configurer, touch terrain or revision, or reset the decoded camera.
  A Dunes fixture skips default-marina reconstruction on both Editor load and
  startup hot reload, because marina terrain edits would corrupt the saved
  Dunes terrain snapshot.
- Water shallowness, overlay grass, and UI now read root runtime from `Editor`.
- Added bounded integration tests in `src/dunes_lab_fixture_test.odin`:
  Dunes fixture load preserves every terrain height/material byte, sea level,
  revision, and decoded camera while rebuilding runtime; Dunes exit and a
  normal fixture load clear stale configuration/runtime; hot-state load
  performs the same terrain-preserving rehydration. Focused result: 3/3 in
  17.019s, zero leaks.
- Passed: fixture codec 2/2 (8.812s), `make check`, and schema check. The
  existing broad Editor-load and lifecycle runners again exited after runner
  startup without an assertion/result and left no Odin process; they were not
  retried. M2 made no schema, version, migration, manifest, or history change.

## M3 evidence — hostile boundary and integration target

- `lab_fixture_preflight` is allocation-free and accepts only `.None` and
  `.Dunes`. Active Dunes config rejects non-finite wind/vegetation and enforces
  wind `[-.62, .62]` and vegetation `[0, 1]`, reporting `lab.kind`,
  `lab.dunes.wind_angle`, or `lab.dunes.vegetation` exactly.
- Editor fixture load executes that preflight before lifecycle preparation or
  stage allocation, so rejected candidates leave the live Editor, terrain, and
  root resources untouched. The bounded container proof covers unknown kind,
  non-finite wind/vegetation, and out-of-range vegetation with input-byte,
  terrain, root, and live-state equality checks. It also disposes errors twice.
- Hot-state load checks the same durable lab boundary before lifecycle binding
  or Dunes rehydration. `dunes_lab_rehydrate` repeats the guard before clearing
  or constructing runtime state. The hot-state integration test writes a
  malformed typed config normally, expects `.Invalid`, preserves a runtime
  sentinel, and proves the decoded terrain was not regenerated.
- `make fixture-dunes-lab-test` now names exactly the three M2 integration
  tests. `make fixture-dunes-lab-preflight-test` names the zero-allocation
  hostile-path test separately.
- Passed: M2 fixture-load integration 1/1 (6.318s); pure lab preflight 1/1
  (87µs), zero leak report; `make fixture-schema-check`; `make check`.
  The initial combined Dunes runner was host-stopped after test-runner startup
  without a result, so neither the three-test M2 target nor the full-container
  hostile test is claimed as passed and neither was retried.
- M3 introduces no schema/version/migration/manifest/history artifact changes.
