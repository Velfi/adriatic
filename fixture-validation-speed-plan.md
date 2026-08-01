# Fixture validation speed

## Goal

Keep fixture-save compatibility proof strong without rebuilding the entire Odin
`src` package once per focused fixture target.

## Milestones

1. **One-compile dev lane** — add `make fixture-dev-test`, running only the
   adjacent migration, current codec, lifecycle, and Editor load/store checks
   in one `odin test src` invocation. Acceptance: one compiler invocation and
   all selected tests pass with zero leaks. **Done:** 5/5 in 2m02 wall time.
2. **One-compile gate lane** — add `make fixture-gate`, running the complete
   fixture test set in one `odin test src` invocation while excluding unrelated
   product/package suites. Acceptance: target coverage is the union of current
   fixture targets and passes with zero leaks. **Done:** 33/33 in 13m48 wall
   time, with `FIXTURE_GATE_TEST_THREADS ?= 2` capping peak RSS at 2.52GB.
3. **Reuse heavy test bytes** — keep canonical current-fixture bytes local to
   each test and remove redundant encodes of identical state. Decode inputs
   remain immutable; hostile mutations use owned copies. Acceptance: same
   fixture behavior and leak guarantees, fewer full encodes without a global
   cache or static artifact. **Done:** current normal codec encodes fell from
   29 to 18, historical helper encodes from 8 to 4, and occupant-case encodes
   from 18 to 12. The portable codec now bulk-copies fixed `[N]u8` and native
   little-endian `[N]f32` arrays while retaining the scalar path on big-endian
   systems. Exact bytes, partial decode mutation, corruption, and ownership
   are covered. `make fixture-dev-test`, `make fixture-gate`, `make check`,
   and `make fixture-schema-check` pass. A normal full fixture is now about
   110 ms to encode and 101 ms to decode.
4. **Scheduled full gate** — run the exact full-gate union in two sequential
   passes: the codec/migration OOM sweeps, hot-state round trip, and
   editor-load/store/upgrade atomic-failure tests at one worker; every other
   fixture test at `FIXTURE_GATE_TEST_THREADS ?= 2`. Acceptance: the two
   derived lists partition the original 33 tests exactly, both passes retain
   leak checks, and `make fixture-gate` runs heavy before light. **Done:**
   the derived lists are exactly 8 heavy plus 25 light. The heavy pass is
   green (8/8, clean exit, 1m53 runner time); the light pass is green (25/25,
   1m12 runner time). The earlier SIGKILL was external.

## Scope

No Fixture schema, manifest, history, codec wire format, migration semantics,
or production game behavior changes. `make test` remains the broad final
product gate.

## Notes

An unbounded default Odin test runner multiplied full-fixture allocations to
about 40GB. The direct dev lane uses one worker because it is the normal edit
loop. The full gate serializes its heavyweight tests, then runs its remaining
checks with two workers. This keeps the exact proof while avoiding a hot-state
round trip and allocation-failure sweep paging together.

## Current phase

Complete.
