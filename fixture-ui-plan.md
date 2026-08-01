# Fixture UI

## Feature

Give fixture save/load actions a visible file path and an in-app file chooser.

## Milestones

1. **Fixture file state** — keep current path and dialog state transient on `Editor`; acceptance: no fixture schema change and empty path means unsaved.
2. **Chooser actions** — save current path directly, open Save As for unsaved Ctrl+S, and open fixture chooser for Ctrl+O and LOAD; acceptance: cancel leaves editor state unchanged.
3. **Editor UI** — show current filepath and status in top bar, add SAVE/LOAD row to left panel, and remove duplicate inspector actions; acceptance: mouse and keyboard actions reach same chooser/save/load paths.
4. **Verification** — build and run focused fixture checks plus schema check; acceptance: all checks pass and feature changes stay in the editor/store/input paths.

## Current phase

Phase 4 — Verify
