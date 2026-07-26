---
name: fix-release
description: Diagnose, repair, publish, and monitor Adriatic GitHub release pipeline failures. Use when a release workflow or platform packaging job fails, when a release tag must be moved to a fix commit, or when asked to fix, retag, and await an Adriatic release.
---

# Fix Adriatic Release

Handle the complete release-repair loop using evidence from the failing jobs and
verify the replacement run through completion.

## Workflow

1. Read the repository `AGENTS.md` instructions and inspect `git status`.
   Preserve unrelated or pre-existing changes.
2. Identify the newest `Release` run and confirm its tag, head SHA, status, and
   URL. Prefer GitHub Actions job metadata and decoded job logs; use `gh` or
   GitHub's public Actions API when needed.
3. Read every failing platform job through the first causal error. Distinguish
   runner/network failures from repository defects. Do not infer success from a
   later skipped step.
4. Inspect the exact workflow, packaging script, Make target, or dependency path
   implicated by each error. Keep fixes product-specific in Adriatic; do not
   modify sibling `zelda-engine` unless the user explicitly expands scope.
5. Implement the smallest fixes that address all observed failures. Common
   release surfaces are:

   - `.github/workflows/release.yml`
   - `.github/workflows/release-macos.yml`
   - `.github/workflows/release-windows.yml`
   - `Makefile`
   - `scripts/package_macos.sh`
   - `scripts/package_windows.ps1`

6. Validate proportionally before publishing:

   - Run `git diff --check`.
   - Parse edited workflow YAML.
   - Syntax-check edited shell scripts.
   - Use dry-run Make output to prove native archives and generated assets are
     prerequisites of the final binary.
   - Run focused local builds or tests when the host supports the target.

7. When the user authorizes publication, stage only the intended changes,
   commit, and push the current branch. Do not discard unrelated changes.
8. If the user authorizes retagging, require a clean tree and run
   `scripts/retag-head.sh <version-without-v>`. This helper fetches the existing
   tag, recreates it at `HEAD`, and force-pushes only that tag.
9. Find the newly triggered `Release` run by matching its `head_sha` to the new
   commit. Do not accidentally monitor an older run with the same tag.
10. Await terminal status. While running, inspect job steps for early failures.
    On failure, fetch the complete failing job logs and repeat the repair loop.
    On success, verify both platform jobs, the publish job, and release
    artifacts before reporting completion.

## Guardrails

- Treat tag force-pushes and release publication as explicit user-authorized
  actions.
- Never claim the release is fixed until its replacement workflow completes
  successfully.
- Report the run URL, commit, tag, platform conclusions, publish conclusion,
  and artifacts in the final handoff.
