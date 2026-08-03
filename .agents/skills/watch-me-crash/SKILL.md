---
name: watch-me-crash
description: Launch Adriatic under LLDB, keep the debugger session alive while a human interactively reproduces a crash, then capture the stopped process state, diagnose the failure, and optionally implement and verify a fix. Use when the user says "watch me crash", asks the agent to observe or debug a live crash reproduction, or wants to reproduce an Adriatic crash while the agent waits in a debugger.
---

# Watch Me Crash

Run Adriatic's validation build under LLDB in a persistent PTY, let the human reproduce the problem in the launched game, and investigate the stopped process without restarting it.

## Start the session

1. Work from the Adriatic repository root.
2. Run `make lldb` with a PTY and a short initial yield. Allow GUI execution and sibling `../zelda-engine` build writes if prompted. This target builds `build/validation/adriatic` with ASAN and Vulkan validation, stages validation assets, and opens LLDB.
3. If the compiler crashes, hangs, miscompiles, or emits clearly incorrect diagnostics, stop immediately. Report the compiler version, command, evidence, and smallest available reproducer. Do not work around it.
4. At the LLDB prompt, send `run` through the same PTY session.
5. Confirm that the game is running and tell the human to reproduce the crash. Keep the returned session ID; do not launch another game or debugger.

Do not use `make run`, attach after launch, or substitute a non-validation build. A reported memory or rendering problem must be reproduced with this validation profile before diagnosis or code changes.

## Wait for the reproduction

- Poll the same PTY with empty writes in bounded intervals, no longer than 30 seconds while actively waiting.
- Treat normal running with no new output as expected. Give the user a concise status update at least once per minute.
- Let the human interact with the game. Do not send input to the game or use the Adriatic MCP unless they request assistance.
- If LLDB stops at an intentional breakpoint or startup trap before the user's repro, inspect the stop reason. Continue only when it is clearly unrelated and safe.
- If the game exits normally or the debugger session disappears before a crash, report that no crash was captured and offer to start a fresh session.

The human may say the repro is complete before LLDB prints a stop. Poll the existing session first. Never infer a crash solely from the user's message.

## Capture crash evidence

Once LLDB stops, keep the process suspended. Record the complete debugger output and run these commands through the existing PTY, adapting only when LLDB reports a command is unavailable:

```text
process status
thread list
thread backtrace all
frame info
register read
frame variable
disassemble --frame --mixed
source list
```

Then:

1. Identify the crashing thread from the stop reason, signal, sanitizer report, or exception.
2. Select that thread and inspect the first relevant project frame. Do not assume frame 0 is the root cause when it is runtime, driver, allocator, or signal machinery.
3. Use `image lookup --address <address>` for unresolved program counters and `image lookup --type <type>` when a relevant value's layout is unclear.
4. Inspect only expressions needed to test concrete hypotheses. Avoid calling functions or mutating variables in the stopped process.
5. Preserve ASAN output and Vulkan validation messages from the terminal alongside the LLDB evidence.

Do not continue, kill, detach, or restart the process until the needed evidence is captured. Ask before discarding a stopped session when further interactive inspection could be useful.

## Diagnose

Trace the failing frame into repository source with `rg` and focused file reads. Separate:

- the immediate failure: signal, invalid access, assertion, sanitizer finding, or Vulkan validation error;
- the corrupt or invalid state that made it possible;
- the earliest source-level cause supported by evidence.

State uncertainty explicitly. Prefer the captured stack, values, validation messages, and source over a speculative explanation. If the evidence is insufficient, request another reproduction with targeted breakpoints or watchpoints and explain exactly what the next run will distinguish.

## Fix only when authorized

Diagnosing the crash does not by itself authorize a code change. If the user asked to fix it, implement the smallest supported correction, preserve unrelated worktree changes, and run focused tests plus `make validation` when the change affects memory or rendering. If the user asked only to watch or debug, report the diagnosis and proposed fix without editing code.

When verifying an interactive crash fix, start a fresh `make lldb` session and ask the human to repeat the same steps. A successful build alone does not prove the crash is fixed.

## Report

Lead with whether the crash was captured. Include:

- stop reason and crashing thread;
- most relevant stack frames and source locations;
- root cause or best-supported hypothesis;
- important sanitizer or Vulkan validation evidence;
- changed files and verification, if a fix was requested;
- the next discriminating step when the result is inconclusive.
