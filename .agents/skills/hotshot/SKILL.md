---
name: hotshot
description: Capture a screenshot from the currently running Adriatic game without restarting it. Trigger whenever the user says "hotshot", asks for a live screenshot, or asks to capture the current game screen.
---

# Hotshot

Capture the next rendered frame from a running Adriatic game.

## Workflow

1. Make sure the game is already running with `rtk make dev`, `rtk make run`, or `rtk make validation`.
2. Run the script directly:
   `rtk python3 tools/live_capture.py --path /absolute/path/to/capture.png --request /absolute/path/to/build/live-capture.request`.
3. Wait for the command to print `Screenshot:`. It returns only after the PNG is written.
4. Show or report the absolute output path.

The default output is `build/captures/adriatic-live.png`. The script only sends a request to the running game; it does not build or launch one. Pass the absolute request path because the game changes its working directory to its executable directory. Make one request at a time. If it times out, check that the game is still running and retry.
